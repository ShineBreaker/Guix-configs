# 构建链与签名注入（Guix 本机）

## JDK：必须用 `:jdk` 输出

```bash
guix shell openjdk@21:jdk -- bash -c 'export JAVA_HOME="$(dirname "$(dirname "$(readlink -f "$(which javac)")")")"; export PATH="$JAVA_HOME/bin:$PATH"; java -version; javac -version'
```

- Guix 的 `openjdk@N` 包是 **JRE**（只有 java），JDK 在 `:jdk` 输出里；不带 `:jdk` 时 `which javac` 直接 command not found。
- `openjdk@21:jdk` 的 `bin/` 里 java 与 javac 都齐，可以用 `readlink -f $(which javac)` 反推 JAVA_HOME——比硬编码 `/gnu/store/...` 安全（store 路径会被 GC 换新）。
- Gradle 8.9 不支持 Java 25 运行（`Unsupported class file major version 69`），必须让 Gradle 跑在 21 上。
- 环境里已有的 `JAVA_HOME` 可能指向一个空目录：显式覆盖，否则报 invalid directory。

## 仓库镜像：`-I` 注入 init script

`dl.google.com` 不可达时，把阿里云 google 镜像排到仓库列表前——**不改仓库文件**（fork 要保持与上游一致、不引入本机专有配置）。

`/tmp/tfm-build/mirror-init.gradle`（任何临时目录都行，只需路径稳定）：

```groovy
// dl.google.com 不可达时用镜像；同时把 AGP 默认要的 build-tools 版本改成本机已装的那个。
def ALIYUN_GOOGLE = 'https://maven.aliyun.com/repository/google'
def ALIYUN_CENTRAL = 'https://maven.aliyun.com/repository/public'

gradle.settingsEvaluated { settings ->
    settings.pluginManagement.repositories {
        maven { url ALIYUN_GOOGLE }
        maven { url ALIYUN_CENTRAL }
    }
}

gradle.allprojects { project ->
    project.buildscript.repositories {
        maven { url ALIYUN_GOOGLE }
        maven { url ALIYUN_CENTRAL }
    }
    project.repositories {
        maven { url ALIYUN_GOOGLE }
        maven { url ALIYUN_CENTRAL }
    }

    // build-tools 版本按本机已装的写，并预先验证这个值在 $ANDROID_HOME/build-tools/ 里存在。
    project.plugins.withId('com.android.application') {
        project.extensions.getByName('android').buildToolsVersion = '35.0.1'
    }
}
```

机制：init script 在项目的 build.gradle 之前执行，所以追加的镜像仓库排在 `google()` 前面；命中镜像后不会再碰不可达域名，也不会报 TLS 错。

## 完整构建命令

```bash
cd <plugin-repo>
guix shell openjdk@21:jdk -- bash -c '
  export JAVA_HOME="$(dirname "$(dirname "$(readlink -f "$(which javac)")")")"
  export PATH="$JAVA_HOME/bin:$PATH"
  ./gradlew -I /tmp/tfm-build/mirror-init.gradle :app:assembleDebug :app:testDebugUnitTest :app:lintDebug --console=plain
'
```

发布路径额外加 `:app:assembleRelease`（R8 压缩，产物约 debug 的 1/3）。产物：
`app/build/outputs/apk/<variant>/termux-float-app_v<version>+<variant>.apk`。

## daemon 不可用时的替代（store 直引，已验证）

`guix shell` 需要 guix daemon（`/var/guix/daemon-socket/socket`）。daemon 没跑时不必停工：store 里通常已留着现成的 openjdk-21 JDK，直接引用即可：

```bash
J="$(ls -d /gnu/store/*openjdk-21*-jdk | head -1)"   # glob 选现存的，别硬编码 hash（会被 GC 换新）
export JAVA_HOME="$J" PATH="$J/bin:$PATH"
export GRADLE_USER_HOME=/home/brokenshine/.local/share/gradle
./gradlew -I /tmp/tfm-build/mirror-init.gradle :app:assembleRelease :app:testDebugUnitTest :app:lintDebug --console=plain
```

- **`GRADLE_USER_HOME` 必须指向 `~/.local/share/gradle`**：wrapper 的 gradle-8.9 发行包（`wrapper/dists/gradle-8.9-all`）与全部 AGP/依赖缓存都在那里；默认的 `~/.gradle` 没有 wrapper 发行包，不显式指定会触发整个 distribution 重新下载。
- glob 命中的目录本身就是 JDK（含 `bin/javac`），无需再 `readlink` 反推。

## 签名注入（app/build.gradle）

```groovy
apply plugin: 'com.android.application'

// 插件与 Termux 主程序必须同签名（sharedUserId）。local.properties 里配了就用它，
// 没配则回退上游 debug testkey —— fork 的通用性不受影响。
def localProperties = new Properties()
def localPropertiesFile = rootProject.file('local.properties')
if (localPropertiesFile.exists()) {
    localPropertiesFile.withInputStream { localProperties.load(it) }
}
def emacsKeystorePath = localProperties.getProperty('emacs.keystore.path')
def emacsKeystore = emacsKeystorePath ? file(emacsKeystorePath) : null
def emacsKeystoreAlias = localProperties.getProperty('emacs.keystore.alias', 'emacs keystore')
def emacsKeystorePassword = localProperties.getProperty('emacs.keystore.password', 'emacs1')

android {
    signingConfigs {
        debug { /* 上游 testkey，保留 */ }
        if (emacsKeystore != null) {
            emacs {
                storeFile emacsKeystore
                storePassword emacsKeystorePassword
                keyAlias emacsKeystoreAlias
                keyPassword emacsKeystorePassword
            }
        }
    }
    buildTypes {
        release { if (emacsKeystore != null) signingConfig signingConfigs.emacs }
        debug { signingConfig emacsKeystore != null ? signingConfigs.emacs : signingConfigs.debug }
    }
}
```

`local.properties`（已 gitignore，不能进仓库）：

```properties
sdk.dir=/home/<user>/Programs/Android/SDK
## GNU Emacs 公开构建密钥的本地副本（alias/password 用默认值）
emacs.keystore.path=/home/<user>/Programs/Android/emacs.keystore
```

## 签名校验（每次构建后都跑）

```bash
APKSIGNER="$ANDROID_HOME/build-tools/$(ls "$ANDROID_HOME/build-tools" | tail -1)/lib/apksigner.jar"
java -jar "$APKSIGNER" verify --print-certs app/build/outputs/apk/debug/*.apk
# 期望：Signer #1 certificate SHA-256 digest: 50b47e8f09b8781fccc998df3fc5c02de0dd9670a3d37e6cacba9f4e76319604
```

Guix 下 build-tools 目录里的 `apksigner` **shell 包装脚本**不可直接执行（报找不到需要的文件）；`java -jar .../lib/apksigner.jar` 正常，签名、verify、打印指纹都能用。

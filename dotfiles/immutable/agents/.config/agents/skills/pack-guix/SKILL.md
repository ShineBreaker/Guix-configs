---
name: pack-guix
description: 'Auto-generate Guix package definitions from binary URLs and source repositories. Handles FHS compatibility for precompiled binaries, generates build scripts, and supports continuous testing. Triggers: "guix package", "打包 guix", "create guix package", "guix define", "guix 打包", "binary to guix".'
---

# Pack-Guix — 自动 Guix 打包 Skill

从预编译 binary 链接和源码仓库链接自动生成 Guix package 定义。
核心能力：源码分析 → hash 计算 → package.scm 生成 → FHS 兼容处理 → 构建验证 → 持续测试。

## 工作流

```
1. 接收输入（binary URL + repo URL）
2. 下载并分析 binary（patchelf --print-interpreter / --print-needed）
3. 克隆仓库分析构建系统（CMake/Meson/Makefile/Gradle 等）
4. 计算 hash（guix hash / sha256sum）
5. 生成 package.scm
6. 处理 FHS 兼容性（patchelf 或 wrapper）
7. 构建验证（guix build）
8. 生成测试脚本
```

## 输入格式

```
pack-guix --binary <URL> --repo <URL> [--name <pkg-name>] [--test-cmd <cmd>]
```

| 参数         | 必需 | 说明                                          |
| ------------ | ---- | --------------------------------------------- |
| `--repo`     | 是   | 源码仓库链接（GitHub/GitLab/Codeberg）        |
| `--binary`   | 否   | 预编译 binary 下载链接（tar.gz/zip/AppImage） |
| `--name`     | 否   | 包名（默认从 repo 名推断）                    |
| `--test-cmd` | 否   | 测试命令（默认 `<pkg-name> --version`）       |

注意：

- 假如没有传入 `--binary` 参数，则尝试从源码构建
- 假如传入了 `--binary` 参数，则需要在包名后面加一个 `-bin` 后缀

## 步骤详解

### （如果传入了 `binary` 参数）步骤 1 ：下载分析 Binary

```bash
# 下载 binary
curl -fsSL -o /tmp/pack-guix-binary "<BINARY_URL>"

# 判断文件类型（归档 vs raw binary）
file /tmp/pack-guix-binary
# 输出示例：
#   "ELF 64-bit LSB executable"  → raw ELF binary，无需解压
#   "gzip compressed data"       → tar.gz 归档，需要 tar 解压
#   "Zip archive data"           → zip 归档，需要 unzip 解压
#   "POSIX tar archive"          → tar 归档

# 如果是归档，解压分析
if file /tmp/pack-guix-binary | grep -qE 'gzip|zip|tar|archive'; then
    mkdir -p /tmp/pack-guix-extract
    if [[ "$BINARY_URL" == *.tar.gz ]] || [[ "$BINARY_URL" == *.tgz ]]; then
        tar xzf /tmp/pack-guix-binary -C /tmp/pack-guix-extract
    elif [[ "$BINARY_URL" == *.zip ]]; then
        unzip -q /tmp/pack-guix-binary -d /tmp/pack-guix-extract
    else
        # 尝试自动检测
        tar xf /tmp/pack-guix-binary -C /tmp/pack-guix-extract 2>/dev/null || \
            unzip -q /tmp/pack-guix-binary -d /tmp/pack-guix-extract 2>/dev/null
    fi
    BINARY_DIR=/tmp/pack-guix-extract
else
    # raw binary，直接分析
    BINARY_DIR=/tmp
fi

# 分析动态链接器依赖
find "$BINARY_DIR" -type f -executable | while read bin; do
  echo "=== $bin ==="
  file "$bin"
  patchelf --print-interpreter "$bin" 2>/dev/null || echo "(no interpreter)"
  patchelf --print-needed "$bin" 2>/dev/null || echo "(no NEEDED)"
done
```

关键判断：

- 如果 binary 需要 `/lib64/ld-linux-x86-64.so.2` → **需要 FHS 兼容处理**
- 记录所有 `NEEDED` 库 → 映射到 Guix 包

注意：

- **即使 `NEEDED` 为空，也要警惕**：Rust/C++ 二进制可能通过 `dlopen` 在运行时加载 native addon（如 `.node`、`.so`），这些 addon 可能依赖 `libgcc_s.so.1` → 需要 `(,gcc "lib")`

### 步骤 2：分析源码仓库

```bash
# 克隆仓库
git clone --depth 1 "<REPO_URL>" /tmp/pack-guix-src
cd /tmp/pack-guix-src

# 检测构建系统
if [ -f CMakeLists.txt ]; then
  BUILD_SYSTEM="cmake"
elif [ -f meson.build ]; then
  BUILD_SYSTEM="meson"
elif [ -f Makefile ] || [ -f GNUmakefile ]; then
  BUILD_SYSTEM="make"
elif [ -f configure.ac ] || [ -f configure.in ]; then
  BUILD_SYSTEM="autoconf"
elif [ -f Cargo.toml ]; then
  BUILD_SYSTEM="cargo"
elif [ -f package.json ]; then
  BUILD_SYSTEM="npm"
elif [ -f go.mod ]; then
  BUILD_SYSTEM="go"
elif [ -f build.gradle ] || [ -f build.gradle.kts ]; then
  BUILD_SYSTEM="gradle"
elif [ -f pyproject.toml ] || [ -f setup.py ]; then
  BUILD_SYSTEM="python"
else
  BUILD_SYSTEM="unknown"
fi
```

### 步骤 3：计算 Hash

- 如果提供了binary:

```bash
# 计算 Guix 格式的 base32 hash
guix hash <binary>
# 或 fallback:
sha256sum <binary> | xxd -r -p | base32 | tr '[:lower:]' '[:upper:]' | sed 's/=*$//'
```

- 如果只提供了源代码：

```bash
# 下载源码归档
SOURCE_URL="<REPO_URL>/archive/refs/tags/v<VERSION>.tar.gz"
curl -fsSL -o /tmp/pack-guix-source.tar.gz "$SOURCE_URL"

# 计算 Guix 格式的 base32 hash
guix hash /tmp/pack-guix-source.tar.gz
# 或 fallback:
sha256sum /tmp/pack-guix-source.tar.gz | xxd -r -p | base32 | tr '[:lower:]' '[:upper:]' | sed 's/=*$//'
```

### 步骤 4：生成 Package Definition

参见 `references/package-template.scm`。

**Binary 包（raw ELF 或单文件下载）：**

```scheme
(define-public <package-name>
  (package
    (name "<name>")
    (version "<version>")
    (source (origin
              (method url-fetch)
              (uri (string-append
                    "<binary-url-prefix>"
                    "v" version "/<binary-file-name>"))
              (sha256 (base32 "<hash>"))))
    (build-system gnu-build-system)
    (arguments
     (list
      #:tests? #f
      #:validate-runpath? #f
      #:strip-binaries? #f
      #:modules '((guix build gnu-build-system)
                  (guix build utils))
      #:phases
      #~(modify-phases %standard-phases
          (delete 'configure)
          (delete 'build)
          (replace 'unpack
            (lambda _
              (copy-file #$source "<binary-name>")
              (chmod "<binary-name>" #o755)))
          (replace 'install
            <ld-linux-wrapper-or-patchelf>))))
    (inputs (list bash-minimal glibc `(,gcc "lib")))
    (home-page "<home-page>")
    (synopsis "<one-line description>")
    (description "<detailed description>")
    (license <license>)
    (supported-systems '("x86_64-linux"))))
```

**归档 binary 包（tar.gz 含多个文件）：**

```scheme
(define-public <package-name>
  (package
    (name "<name>")
    (version "<version>")
    (source (origin
              (method url-fetch)
              (uri (string-append
                    "<binary-url-prefix>"
                    "v" version "/<archive-name>.tar.gz"))
              (sha256 (base32 "<hash>"))))
    (build-system copy-build-system)
    (arguments
     (list
      #:tests? #f
      #:validate-runpath? #f
      #:strip-binaries? #f
      #:install-plan
      '("(" ("bin/<binary-name>" "bin/<pkg-name>"))
      ...))
    ...))
```

**源码构建包：**

```scheme
(define-public <package-name>
  (package
    (name "<name>")
    (version "<version>")
    (source (origin
              (method git-fetch)
              (uri (git-reference
                    (url "<repo-url>")
                    (commit (string-append "v" version))))
              (file-name (git-file-name name version))
              (sha256 (base32 "<hash>"))))
    (build-system <build-system>)
    (inputs (list <dependencies>))
    (home-page "<home-page>")
    (synopsis "<one-line description>")
    (description "<detailed description>")
    (license <license>)))
```

**注意**：

- Binary 包用 `url-fetch` + `gnu-build-system`（raw ELF）或 `copy-build-system`（归档）
- 源码包用 `git-fetch` + 对应的 `build-system`

### 步骤 5：FHS 兼容处理

预编译 binary 的必需构建参数：

```scheme
(arguments
 (list
  #:tests? #f                  ; 无源码，不运行测试
  #:validate-runpath? #f      ; 跳过 RUNPATH 验证（binary 依赖 FHS ld-linux）
  #:strip-binaries? #f        ; 避免 strip 破坏嵌入资源
  ...))
```

**方案 A：patchelf（推荐用于从源码构建的包）**

```scheme
(add-after 'install 'patch-binaries
  (lambda* (#:key outputs #:allow-other-keys)
    (let ((out (assoc-ref outputs "out")))
      (for-each (lambda (bin)
                  (invoke "patchelf"
                          "--set-interpreter"
                          (string-append (assoc-ref inputs "glibc")
                                         "/lib/ld-linux-x86-64.so.2")
                          bin))
                (find-files (string-append out "/bin") ".*")))))
```

**方案 B：ld-linux Wrapper（推荐用于预编译 binary 包）**

不修改 binary，通过 Guix 的 `ld-linux` 动态链接器启动 binary：

```scheme
(replace 'install
  (lambda* (#:key inputs #:allow-other-keys)
    (let* ((out #$output)
           (bin (string-append out "/bin"))
           (libexec (string-append out "/libexec"))
           (ld.so (string-append (assoc-ref inputs "glibc")
                                 #$(glibc-dynamic-linker)))
           ;; 拼接 library-path，可包含多个路径
           (lib-path (string-join
                      (list (string-append (assoc-ref inputs "glibc") "/lib")
                            (string-append (assoc-ref inputs "gcc") "/lib"))
                      ":")))
      (mkdir-p libexec)
      (install-file "<binary-name>" libexec)
      (mkdir-p bin)
      (call-with-output-file (string-append bin "/<pkg-name>")
        (lambda (port)
          (format port
                  "#!~a\nexec ~a --argv0 ~a/<binary-name> --library-path ~a ~a/<binary-name> \"$@\"\n"
                  #$(file-append bash-minimal "/bin/sh")
                  ld.so
                  libexec
                  lib-path
                  libexec)))
      (chmod (string-append bin "/<pkg-name>") #o755))))
```

注意：

- `--argv0` 确保 binary 通过 `argv[0]` 自定位时能正确找到自身路径
- `--library-path` 为运行时 `dlopen` 加载的 native addon（如 `.node` 文件）提供库搜索路径
- 即使 binary 本身 `NEEDED` 为空，只要它加载了外部 native addon，就需要包含 `gcc` 的 lib 路径（提供 `libgcc_s.so.1`、`libstdc++.so.6`）

### 步骤 6：构建验证

```bash
# 在 Guix 环境中测试构建
guix build -f package.scm --dry-run    # 先 dry-run
guix build -f package.scm              # 实际构建

# 验证安装后 binary 基础运行
guix shell -f package.scm -- <pkg-name> --version

# 运行时二次验证（关键！）
# 某些依赖只在运行时通过 dlopen 暴露，build 阶段无法发现。
# 如果 binary 加载 native addon（如 .node、.so），确保：
#   1. addon 能被正确找到（可能需要 LD_LIBRARY_PATH 或 --library-path）
#   2. addon 的 NEEDED 库（如 libgcc_s.so.1）在 library-path 覆盖范围内
#   3. 如果报错 "cannot open shared object file"，补充对应的 Guix 包到 inputs
```

### 步骤 7：生成测试脚本

参见 `references/test-template.sh`。

测试脚本包含：

1. 包定义加载验证
2. 构建测试（dry-run + 实际构建）
3. Binary 运行测试
4. FHS 兼容性验证（动态链接器检查）
5. 持续测试循环（可选）

## 持续测试

用户要求支持持续测试。生成以下文件：

### `test.sh` — 单次测试

```bash
#!/usr/bin/env bash
set -euo pipefail

PACKAGE_FILE="${1:-package.scm}"
TEST_CMD="${2:-<pkg-name> --version}"

echo "=== 加载验证 ==="
guix build -f "$PACKAGE_FILE" --dry-run

echo "=== 构建测试 ==="
guix build -f "$PACKAGE_FILE"

echo "=== 运行测试 ==="
guix shell -f "$PACKAGE_FILE" -- $TEST_CMD
```

### `watch-test.sh` — 持续测试

```bash
#!/usr/bin/env bash
set -euo pipefail

PACKAGE_FILE="${1:-package.scm}"
TEST_CMD="${2:-<pkg-name> --version}"

echo "持续测试模式：监控 package.scm 变化自动重建"

inotifywait -m -e modify -e create -e delete \
  --format '%w%f' "$PACKAGE_FILE" | while read changed; do
  echo "[$(date '+%H:%M:%S')] 检测到变化: $changed"
  echo ">>> 重新构建..."
  guix build -f "$PACKAGE_FILE" 2>&1 | tail -5
  echo ">>> 运行测试..."
  guix shell -f "$PACKAGE_FILE" -- $TEST_CMD 2>&1 | tail -3
  echo "--- 完成 ---"
done
```

## 依赖映射表

Binary 的 `patchelf --print-needed` 输出 → Guix 包映射：

| 库名                     | Guix 包    |
| ------------------------ | ---------- |
| libc.so.6                | glibc      |
| libstdc++.so.6           | gcc:lib    |
| libm.so.6                | glibc      |
| libpthread.so.0          | glibc      |
| libdl.so.2               | glibc      |
| libz.so.1                | zlib       |
| libssl.so / libcrypto.so | openssl    |
| libcurl.so.4             | curl       |
| libfuse.so.2             | fuse       |
| libX11.so.6              | libx11     |
| libGL.so.1               | libglvnd   |
| libasound.so.2           | alsa-lib   |
| libpulse.so.0            | pulseaudio |

## 输出文件清单

执行完成后产出：

| 文件              | 说明                      |
| ----------------- | ------------------------- |
| `package.scm`     | Guix 包定义（核心产出）   |
| `test.sh`         | 单次测试脚本              |
| `watch-test.sh`   | 持续测试脚本              |
| `BUILD-NOTES.org` | 构建笔记（Org mode 格式） |

**注意**: `package.scm` 生成并测试完成之后，需要在 `modules/jeans/packages` 中寻找到一个合适的分类，并将其拼合进去

## 注意事项

1. **许可证检测**：从仓库 LICENSE 文件自动检测，不确定时标注 `license:nonfree`
2. **版本推断**：优先使用 git tag，其次 binary URL 路径或文件名中的版本号
3. **架构限制**：如果 binary 仅 x86_64，添加 `(supported-systems '("x86_64-linux"))`
4. **预编译 binary 包的构建系统选择**：
   - **raw ELF 单文件**（如 `omp-linux-x64`）→ `gnu-build-system` + `replace 'unpack` 用 `copy-file`
   - **归档文件**（tar.gz / zip / AppImage）→ `copy-build-system` 或 `gnu-build-system` + 解压逻辑
   - 避免盲目使用 `trivial-build-system`，它不适合需要复杂 install 阶段的 binary
5. **FHS 警告**：如果检测到 `/lib64/ld-linux-x86-64.so.2` 依赖，必须在 package.scm 中处理（wrapper 或 patchelf）
6. **运行时依赖陷阱**：即使 `patchelf --print-needed` 返回空，运行时通过 `dlopen` 加载的 native addon（常见：Rust 二进制里的 N-API `.node` 文件、Electron app 的 `.so`）仍可能依赖 `libgcc_s.so.1` 或 `libstdc++.so.6`。构建成功后务必运行一次完整的功能测试。

## 与知识库联动

打包完成后：

1. `kb search "guix package"` 检查是否已有类似经验
2. 如有新发现（特殊依赖、特殊构建步骤）→ `kb add` 记录
3. 更新 `BUILD-NOTES.org` 作为可复用的打包经验

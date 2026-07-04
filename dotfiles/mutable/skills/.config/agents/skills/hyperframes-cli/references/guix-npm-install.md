---
name: hyperframes-cli / guix-npm-install
description: How to install `hyperframes` (or any npm CLI) on a Guix system where `npm install -g` fails because `/gnu/store/...` is read-only. Read this the first time `npx hyperframes` returns "npx canceled due to missing packages".
---

# Guix / Nix 系统下的 npm 全局安装修复

## 症状

```
npm error code ENOENT
npm error syscall mkdir
npm error path /gnu/store/ycqil1z6y4jccjzixw6kfbk01c6mpjyz-node-22.14.0/lib/node_modules/hyperframes
npm error errno -2
npm error enoent ENOENT: no such file or directory, mkdir ...
```

`npm install -g` 默认 prefix 指向 `$(which node)/../lib/node_modules`,Guix/Nix 的 node 装在 `/gnu/store/...` 是只读的,mkdir 必然失败。

## 修复(2 步, 永久)

```bash
# 1. 把 npm 全局 prefix 改到用户目录
mkdir -p ~/.npm-global
npm config set prefix ~/.npm-global

# 2. 装包
npm install -g hyperframes@0.7.3   # 或最新版本
# → ~/.npm-global/bin/hyperframes 出现
```

## 让新装的可执行文件能被找到

`~/.npm-global/bin` 不在默认 `$PATH` 里。三种加法:

1. **本会话临时**:`export PATH=~/.npm-global/bin:$PATH`
2. **当前用户永久**(推荐):塞进 `~/.bashrc` 或 `~/.profile`:
   ```bash
   export PATH="$HOME/.npm-global/bin:$PATH"
   ```
3. **Guix 用户走 home-shepherd/services**:在 `~/Projects/Config/Guix-configs/source/config.org` 里给 `home-environment-variables` 加 `PATH` 拼接,然后 `blue home` 部署。

## 验证

```bash
which hyperframes        # → /home/<user>/.npm-global/bin/hyperframes
hyperframes --version    # → 0.7.x
hyperframes doctor       # 全面环境检查,至少 Node/FFmpeg/Chrome 通过即可 render
```

## 跑 init/lint/render 的标准姿势

```bash
export PATH=~/.npm-global/bin:$PATH
cd /tmp/<project>         # 或任何工作目录
hyperframes init <name> --non-interactive --skip-skills --example=blank
cd <name>
# 写 index.html ...
hyperframes lint          # 静态检查
hyperframes validate      # 运行时 + 对比度
hyperframes inspect       # 真实渲染抽样
hyperframes render --output renders/video.mp4
```

## 适用范围

- 任何 Guix/Nix 系统
- 任何用 `npm install -g` 失败的 CLI(`@puppeteer/browsers install chrome-headless-shell` 也走 npm,同样踩坑)
- 不适用于:系统包管理器(apt/pacman/guix)能装的包——优先用系统包,不要绕到 npm

## 已知无害警告

`hyperframes doctor` 在 Guix 上几乎一定报:

- `✗ Docker Not found` —— `--docker` 标志用不了,普通 `render` 不受影响
- `Using system Chrome ... falls back to screenshot mode` —— chrome-headless-shell 没装,自动降级,产物正常

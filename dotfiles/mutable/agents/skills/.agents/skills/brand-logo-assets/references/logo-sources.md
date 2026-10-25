# Logo 源探测结论

按本机实测整理的可靠源；标「失效」的别再试。

## 有效的源

| 目标 | 可用 URL / 命令 | 备注 |
| --- | --- | --- |
| simple-icons 全量索引 | `curl -s https://data.jsdelivr.com/v1/packages/npm/simple-icons@latest?structure=flat \| tr ',}' '\n\n'` | 拿完整 slug 列表；`icons/<slug>.svg` 单取确认 |
| simple-icons slug/hex 索引 | `https://cdn.jsdelivr.net/npm/simple-icons@latest/_data/simple-icons.json` | title + hex + aka alias，做 slug 映射的权威 |
| GitHub 资产树（限流规避） | `gh api repos/<o>/<r>/git/trees/<branch>?recursive=1 --jq '.tree[].path'` | 本机 `gh` 已登录时免限流；裸 `api.github.com` 会 403 |
| raw.githubusercontent 单文件 | `https://raw.githubusercontent.com/<o>/<r>/<branch>/<path>` | 高频并发下载会有 429，控制并发或重试 |
| Wikimedia 官方 logo | `https://commons.wikimedia.org/wiki/Special:FilePath/<File%20Name>.svg` | simple-icons 未收录品牌的主力源 |
| vectorlogo.zone | `https://www.vectorlogo.zone/logos/<vendor>/<vendor>-icon.svg` | 语言类图标（Java 等）可用；非所有 vendor 都有 |
| 官网真实 logo 资产 | 扒首页 HTML：`grep -oE '(src\|href)="[^"]*(logo\|icon\|favicon)[^"]*"'` | 下一步的 `/_next/image?url=%2Fassets%2Flogo%2F*.webp` 常带高分辨率原图 |

## 失效 / 绕远路的路径

| 路径 | 现象 | 改用 |
| --- | --- | --- |
| `cdn.simpleicons.org/<slug>` | 403（非浏览器 Referer） | 走 jsdelivr npm 路径 |
| jsdelivr gh 大包 assets | 403 `Package size exceeded the configured limit of 50 MB` | `gh api` 资产树 |
| 未认证 GitHub REST API | 403 `API rate limit exceeded` | 本机 `gh` CLI |
| `git.savannah.gnu.org/cgit/...?h=master` | 301 后 404（GNU Guix 系） | Guix 系走官方 artwork 仓库：`git clone --depth 1 https://codeberg.org/guix/artwork.git`，`logo/` 与 `backgrounds/` |
| guix checkout 里的 `misc/logo` | 那份是 **Godot Engine Logo**（见同目录 LICENSE.txt），不是 Guix 标志 | codeberg.org/guix/artwork |
| 官网 `/logo.svg` 未部署 | 整站 200 + HTML（Next.js fallback 页） | 扒 HTML 里的真实资产 URL |
| codeberg raw 未传 SVG | 404 | GitHub 镜像或 Wikimedia |

## 本机资产的常见位置

- `~/.local/share/icons/hicolor/scalable/apps/<app>.svg` — 自建/打包脚本装的 GUI 应用
- `~/.guix-home/profile/share/icons/hicolor/scalable/apps/<app>.svg` — Guix profile 装的包
- `$APP_HOME/assets/*.svg`（如 Hermes Agent 的 `icon-master.svg`）— Electron/Tauri 应用自带
- 本地源码树 `public/logo/icons/<size>.png` — 自己有源码的项目

## 判定真身的文件头

| 类型 | 前几字节 |
| --- | --- |
| SVG | `<svg`（lstrip 后） |
| PNG | `\x89PNG\r\n\x1a\n` |
| ICO | `\x00\x00\x01\x00` |
| WEBP | `RIFF` … `WEBP` |

官网 404 兜底页与 favicon.ico 都可能返回 200，必须按文件头判型，不能信扩展名。

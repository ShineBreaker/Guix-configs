---
name: nix-github-api-auth
description: nix 访问 GitHub API 被 403 限流时配置 access-tokens 认证。
version: 1.0.0
metadata:
  hermes:
    tags: [nix, github, authentication, rate-limit, access-tokens]
---

# nix-github-api-auth — nix 访问 GitHub API 的认证配置

## When to Use

- `nix flake update` / `nix build` 输出 `api.github.com ... HTTP error 403` + `API rate limit exceeded` + `using cached version`
- 需要给 nix 配 GitHub token（access-tokens），且 token 不想进 git 仓库 / nix store
- home-manager / nix.conf 场景下排查 access-tokens 配置为何 401

## 症状识别

```text
warning: error: unable to download 'https://api.github.com/repos/<owner>/<repo>/commits/HEAD': HTTP error 403
       {"message":"API rate limit exceeded for <IP>..."}; using cached version
```

- 触发场景：`nix flake update` / `nix build` 解析 `github:` 或 registry（`nixpkgs/nixos-unstable`）输入时，nix 要查 `api.github.com/.../commits/HEAD`
- 根因：**未认证**请求按 IP 限流 60 次/小时（403）；nix 随后回退 lock/缓存版本（"using cached version"），表现是 flake 更新不到最新
- 区分 403 vs 401：403 = 未认证/限流；401 Bad credentials = 带了 token 但无效（往往是配置被当字面量或 token 有尾随换行）

## 正确解法：access-tokens

nix 手册（2.24+）确认：`access-tokens` 只接受**内联 token**：

```ini
access-tokens = github.com=ghp_xxx
```

认证后额度升到 5000/h。生效位置三选一：

1. **nix.conf 直接写**（token 明文进配置文件）
2. **home-manager**：`nix.settings.access-tokens = "github.com=..."`（会进 nix store，本机可读）
3. **token 不进任何配置文件**（推荐，见下）

## 推荐：NIX_USER_CONF_FILES 私有文件方案

token 保持 0600 私有文件，不落 git / 不进 store：

```bash
# 1. 建私有配置（token 从 gh 登录态提取）
printf 'access-tokens = github.com=%s\n' "$(gh auth token)" > ~/.config/nix/gh-token.conf
chmod 600 ~/.config/nix/gh-token.conf

# 2. 环境变量（放 shell profile / Guix Home 环境变量服务 / 系统 profile）
export NIX_USER_CONF_FILES="$HOME/.config/nix/gh-token.conf:$HOME/.config/nix/nix.conf"
```

⚠ **关键坑**：设置 `NIX_USER_CONF_FILES` 后 nix **不再自动读** XDG 位置的 `~/.config/nix/nix.conf`——必须把原来的 nix.conf 也列入，否则 substituters 等全丢。顺序无键冲突时随意；有冲突时靠前文件最后加载（覆盖）。

## 反模式（全部实测踩过）

| 写法 | 结果 |
| --- | --- |
| `access-tokens = github.com=file:/path/to/token` | ❌ **`file:` 语法不存在**（那是 `builders` 的 `@path`）。nix 把 `file:/path` 当字面 token 发送 → **401 Bad credentials** |
| token 文件带尾随换行（`gh auth token > file` 默认有） | ❌ 401。nix 不 trim，必须 `tr -d '\n'`（shell `$(cat)` 命令替换会去换行，所以 curl 测试通过但 nix 失败——最迷惑的假阳性） |
| home-manager 配置里 `builtins.readFile /home/...` 注入 token | ❌ home-manager switch 默认 **pure eval**，绝对路径 readFile 被禁（`--impure` 可解但需改命令） |
| `nix --extra-config` 放在子命令后 | ❌ 是全局 flag，放子命令前；`NIX_CONFIG` 环境变量更稳 |
| 裸 `curl` 测 token 有效就以为 nix 能用 | ❌ 需注意换行差异（见上） |

## 验证流程

```bash
# 1. token 本身有效（curl 层）
curl -s -o /dev/null -w '%{http_code}\n' -H "Authorization: Bearer $(cat <token-file>)" \
  https://api.github.com/repos/nix-community/home-manager/commits/HEAD   # 期望 200

# 2. 额度确认
curl -s -H "Authorization: Bearer $(cat <token-file>)" https://api.github.com/rate_limit \
  | python3 -c "import json,sys; c=json.load(sys.stdin)['resources']['core']; print(c['used'], c['limit'], c['remaining'])"

# 3. nix 层端到端（不污染 lock 文件：先备份再还原）
cp flake.lock /tmp/flake.lock.bak
NIX_CONFIG="access-tokens = github.com=$(cat <token-file>)" nix flake update --flake <dir>
cp /tmp/flake.lock.bak flake.lock
# 无 403/401、出现 "updating lock file" = 通过
```

## token 生命周期

- gh OAuth token（`~/.config/gh/hosts.yml`）重新 `gh auth login` 后要同步更新私有 conf
- `NIX_USER_CONF_FILES` 方案下更新 = 改一个 0600 文件，无部署动作

## 案例

Guix-configs 仓库（blue nix-update 二轨链）的完整落地过程见 `references/guix-configs-nix-chain-case.md`。

# Guix-configs 仓库 nix 备用链认证落地案例（2026-08-13）

## 背景

`blue nix-update` 报 GitHub API 403（rate limit exceeded for 54.116.42.24）。命令构成（blueprint.scm `nix-update-command`）：

```scheme
(%run '("nix-channel" "--update"))
(%run `("nix" "flake" "update" "--flake" ,%nix-dir))          ; %nix-dir = <repo>/source/nix
(%run `("git" "commit" "-S" "-m" "build(flake.lock): bump flake inputs" ...))
```

flake 输入全部是 `github:` 引用（codex-desktop-linux / home-manager / llm-agents.nix / registry nixpkgs），解析时未认证打 api.github.com → 限流 403 → 回退缓存。

## 落地内容

1. **私有 token 配置** `~/.config/nix/gh-token.conf`（0600）：
   ```
   access-tokens = github.com=gho_xxx   # 来自 ~/.config/gh/hosts.yml 的 gh 登录 token
   ```
2. **环境变量** `source/config.org` 的 `extend-environment-variables` 块（`environment-variable-services` 组装进 `home-environment-variables-service-type`）：
   ```scheme
   ("NIX_USER_CONF_FILES" . "$HOME/.config/nix/gh-token.conf:$HOME/.config/nix/nix.conf")
   ```
   注意 nix.conf 是 home-manager 生成的软链（store 只读副本），**不能手改**；改配置源 `source/nix/configuration/00-main/nix.nix` 的 `nix.settings` 后 `blue nix`（home-manager switch）重新生成。

## 排查顺序（可复用的诊断路径）

1. `gh` CLI 不在 PATH → 从 `~/.config/gh/hosts.yml` 正则提取 oauth_token（40 字符）
2. curl 带 token 测 `commits/HEAD` → 200，确认 token 有效
3. nix 注入测试：`NIX_CONFIG="access-tokens = github.com=<token>" nix flake update` → 401 消失 → 证明 client 读配置
4. 逐个排除：`file:` 语法不存在（401）→ token 尾随换行（401）→ 最终 NIX_USER_CONF_FILES 方案通过（无 403/401，额度 5000/h）

## 验证

- `blue check` 括号检查通过
- `NIX_USER_CONF_FILES=... nix flake update --flake source/nix`：无 403/401，输出 "updating lock file"
- 验证时不污染 flake.lock：`cp flake.lock /tmp/xxx.bak` 跑完还原

## 后续维护

- gh 重新 `auth login` 后同步更新 `~/.config/nix/gh-token.conf`
- `source/nix/configuration/programs/*.nix` 有用户未提交改动时，`blue nix` switch 会一并构建（首次构建下载量大，几十 GB 依赖闭包属正常）

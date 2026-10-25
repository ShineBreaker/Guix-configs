# 探测命令集

按需取用，都是只读。全部在 `$HOME` 下跑，不改任何东西。

## 并行 du（HOME 顶层）

```bash
scan() { local d="$1" sz; [ -d "$d" ] || return 0
  sz=$(timeout 180 du -sh "$d" 2>/dev/null | cut -f1)
  [ -n "${sz:-}" ] && printf '%s\t%s\n' "$sz" "${d/#$HOME\//~/}"; }
export -f scan
{ for d in "$HOME"/*/ "$HOME"/.[!.]*/; do [ -d "$d" ] && printf '%s\0' "$d"; done; } \
  | xargs -0 -P 4 -I{} bash -c 'scan "$@"' _ {} | sort -rh | head -15
```

顶层散落文件：`ls -la "$HOME" | grep -v '^d'`。

## 判活：mtime + 仓库引用（两条都要）

```bash
# 目录内最新文件时间
timeout 30 find "$dir" -type f -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1

# 是否被 dotfiles 仓库引用（在用 = 别动）
cd ~/Projects/Config/Guix-configs && git grep -il "<name>" | head -2
```

`git grep` 无命中只说明仓库没引用它，不等于能删——判据是「mtime 旧」且「无引用」同时成立，且**用户确认过**。

## 仓库同步债

```bash
find ~/Projects -maxdepth 3 -name .git -type d | sed 's|/.git$||' | sort | while read -r r; do
  cd "$r" 2>/dev/null || continue
  dirty=$(git status --porcelain 2>/dev/null | wc -l)
  unpushed=$(git rev-list --count @{u}..HEAD 2>/dev/null || echo NOUP)
  behind=$(git rev-list --count HEAD..@{u} 2>/dev/null || echo '?')
  [ "$dirty" != 0 ] || [ "$unpushed" != 0 ] || [ "$unpushed" = NOUP ] \
    && printf '%-46s dirty=%-4s unpushed=%-5s behind=%s\n' "${r/#$HOME\//~/}" "$dirty" "$unpushed" "$behind"
done
```

只列有问题的；clean 的仓库刷屏只会淹没真正的债。

## git remote 内嵌 token 扫描

```bash
find ~/Projects -maxdepth 3 -name .git -type d 2>/dev/null | while read g; do
  git --git-dir="$g" remote get-url origin 2>/dev/null | grep -qE '://[^/]+@' && echo "${g%/.git}"
done
```

两种命中形态：`x-access-token:<token>@`（token 明文）和 `<user>@github.com`（会触发密码输入，同样断无人值守）。

修法：指纹比对确认与 `gh auth token` 是同一把（sha256 两侧，**都不打印**），同则洗干净 URL 让 helper 链供凭据：

```bash
git remote set-url origin https://github.com/<owner>/<repo>.git
```

验证必须**无头**：

```bash
env -u DBUS_SESSION_BUS_ADDRESS -u DISPLAY bash -c 'cd <repo> && git push --dry-run origin HEAD:<branch>'
```

前台 `--dry-run` 通过不算数——前台可能吃着 GUI 解锁的凭据。

## 无头凭据链路：谁在真正供凭据

逐个 helper 隔离测试，别凭第一条报错下结论：

```bash
export PATH="$HOME/.guix-home/profile/bin:$PATH"
for h in store cache 'keepassxc --git-groups' '!gh auth git-credential'; do
  got=$(printf 'protocol=https\nhost=github.com\n' | timeout 12 \
    git -c credential.helper= -c "credential.https://github.com.helper=$h" credential fill 2>&1 \
    | grep -c '^password=.\+')
  printf '%-30s → %s\n' "$h" "$([ "$got" -gt 0 ] && echo '供凭据' || echo '不供')"
done
```

链式回退：失败的环节打印的 `command not found` 一类是噪声，只有最后的成功者在供凭据。

## 包管理器缓存

```bash
for c in uv npm pnpm pip cargo guix nix rattler thumbnails; do
  d="$HOME/.cache/$c"; [ -e "$d" ] && du -sh "$d" 2>/dev/null
done
```

## Guix 代数（判断 gc 有没有意义）

```bash
ls -1d /var/guix/profiles/per-user/$USER/guix-home-*-link 2>/dev/null | wc -l
ls -1d /var/guix/profiles/per-user/$USER/guix-profile-*-link 2>/dev/null | wc -l
```

代数少 ⇒ store 基本是活跃内容，别把 gc 当回收大头。

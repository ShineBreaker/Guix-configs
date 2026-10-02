#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
# SPDX-License-Identifier: MIT
#
# sync-agenote.sh — 按锁文件拉取钉版本 tag 的 agenote 组件，并铺到宿主目录。
#
# 为什么不是 submodule（ADR 0005）：
#   submodule 推进要三步——子仓 push、bump 父仓指针、push 父仓。漏第三步时
#   本地一切正常、远端指针仍是旧值，症状极隐蔽（历史上已在 tag 漏推上栽过）。
#   本脚本把「版本」变成一个可 code review 的纯文本锁文件：版本变更就是改
#   一行，天然原子，且不可能漏推。
#
# 组件装哪：
#   agenote-skills → ~/.config/agents/skills/          （agenote-{base,curator,review}）
#   agenote-pi     → ~/.config/omp/extensions/agenote-hooks/
#   agenote-zcode  → ~/.zcode/plugins/agenote-zcode/
#   agenote-hermes → ~/.local/share/hermes/plugins/agenote/
#   agenote（CLI）、agenote-el、dsh-agenote 不由本脚本部署——分别走
#   uv tool install / package.el / npm install，见 monorepo 的 README。
#
# 链接方式：逐文件相对 symlink（与本脚本落地前 dotfiles 侧的既有形态一致），
# 指向内容寻址缓存 ~/.local/share/agenote/packages/<pkg>/<version>/。
# 缓存多版本共存，切版本只改锁文件，不需要重新下载。
#
# 用法：
#   ./sync-agenote.sh            # 拉取 + 铺设（先全部下载校验通过再动任何链接）
#   ./sync-agenote.sh --dry-run  # 只报告将要做什么
#   ./sync-agenote.sh --check    # 只校验锁文件与已装缓存是否一致
#   ./sync-agenote.sh --uninstall # 移除本脚本创建的链接（按 manifest 精确回滚）

set -euo pipefail

readonly SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOCK_FILE="${AGENOTE_LOCK:-${SELF_DIR}/agenote.lock}"
readonly CACHE_ROOT="${AGENOTE_CACHE_ROOT:-${XDG_CACHE_HOME:-$HOME/.cache}/agenote/packages}"
readonly MANIFEST="${AGENOTE_MANIFEST:-${XDG_STATE_HOME:-$HOME/.local/state}/agenote/sync-manifest}"
readonly REPO="${AGENOTE_REPO:-ShineBreaker/agenote}"

# 包 → 宿主目标目录（相对 $HOME）。顺序即铺设顺序，无依赖关系。
declare -A TARGETS=(
  [agenote-skills]='.config/agents/skills'
  [agenote-pi]='.config/omp/extensions/agenote-hooks'
  [agenote-zcode]='.zcode/plugins/agenote-zcode'
  [agenote-hermes]='.local/share/hermes/plugins/agenote'
)

DRY_RUN=0
MODE=sync

# ─── 工具 ────────────────────────────────────────────────────
log()  { printf '%s\n' "$*" >&2; }
die()  { printf '✗ %s\n' "$*" >&2; exit 1; }

need() { command -v "$1" >/dev/null 2>&1 || die "缺少必需命令：$1"; }

# ─── 锁文件 ─────────────────────────────────────────────────
# 格式刻意最简：`pkg:version:sha256` 每行一个，纯文本、diff 友好、无需解析器。
# sha256 取自 monorepo 发布时生成的 dist/<pkg>/SHA256SUMS。
declare -A LOCK_VER LOCK_SHA

load_lock() {
  [[ -f "$LOCK_FILE" ]] || die "锁文件不存在：$LOCK_FILE"
  local line pkg ver sha
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"                       # 去行尾注释
    line="$(printf '%s' "$line" | tr -d '[:space:]')"
    [[ -z "$line" ]] && continue
    IFS=':' read -r pkg ver sha <<<"$line"
    [[ -n "$pkg" && -n "$ver" && -n "$sha" ]] || die "锁文件行格式错误（应为 pkg:version:sha256）：$line"
    [[ -n "${TARGETS[$pkg]:-}" ]] || die "锁文件含未知组件 '$pkg'（本脚本只铺 ${!TARGETS[*]}）"
    LOCK_VER[$pkg]="$ver"
    LOCK_SHA[$pkg]="$sha"
  done <"$LOCK_FILE"
  ((${#LOCK_VER[@]} > 0)) || die "锁文件为空：$LOCK_FILE"
}

# ─── 下载与校验 ─────────────────────────────────────────────
# 产物 tarball 顶层目录名由构建器决定（当前是包名），故这里不硬编码，
# 而是解包后**探测唯一顶层目录**——这样构建器改了命名不必同步改本脚本。
top_dir_of() {
  local dir="$1" entries
  mapfile -t entries < <(find "$dir" -mindepth 1 -maxdepth 1)
  if ((${#entries[@]} != 1)) || [[ ! -d "${entries[0]}" ]]; then
    die "产物结构异常：期望恰好一个顶层目录，实际有 ${#entries[@]} 项——$(ls -A "$dir")"
  fi
  printf '%s' "${entries[0]}"
}

# tag = <包>-v<版本>（monorepo 的发布约定，见 ADR 0005）。
tag_of() { printf '%s-v%s' "$1" "$2"; }

# 资产名 = <包>-<版本>.tar.gz（构建器 tools/release/build.py 产出）。
asset_url() {
  local pkg="$1" ver="$2"
  printf 'https://github.com/%s/releases/download/%s/%s-%s.tar.gz' \
    "$REPO" "$(tag_of "$pkg" "$ver")" "$pkg" "$ver"
}

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

# 返回 0 表示缓存里已是校验通过的该版本。
ensure_cached() {
  local pkg="$1" ver="$2" sha="$3"
  local dest="$CACHE_ROOT/$pkg/$ver" stamp="$CACHE_ROOT/$pkg/$ver.sha256"
  if [[ -f "$stamp" && "$(cat "$stamp")" == "$sha" && -d "$dest" ]] \
     && [[ -n "$(top_dir_of "$dest" 2>/dev/null || true)" ]]; then
    return 0
  fi
  [[ "$MODE" == check ]] && return 1
  need curl; need tar
  local tmp; tmp="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" RETURN
  local url; url="$(asset_url "$pkg" "$ver")"
  log "  下载 $pkg $ver（$(tag_of "$pkg" "$ver")）"
  curl -fsSL --retry 3 -o "$tmp/pkg.tar.gz" "$url" \
    || die "下载失败：$url
    （确认 monorepo 已发布 $(tag_of "$pkg" "$ver") 的 GitHub Release 资产）"
  local got; got="$(sha256_of "$tmp/pkg.tar.gz")"
  [[ "$got" == "$sha" ]] || die "$pkg-$ver.tar.gz 校验和不符
    锁文件 sha256: $sha
    实际     sha256: $got
    两者不符通常意味着 Release 资产被替换过——先人工核实再改锁文件。"
  mkdir -p "$dest" "$CACHE_ROOT/$pkg"
  tar -xzf "$tmp/pkg.tar.gz" -C "$dest"
  printf '%s' "$sha" >"$stamp"
  top_dir_of "$dest" >/dev/null   # 结构自检，失败即 die
  log "  ✓ 已校验并缓存 $pkg $ver"
}

# ─── 铺设 ───────────────────────────────────────────────────
# 逐文件相对 symlink。目标里已存在**非 symlink** 的同名文件一律拒写——
# 那多半是用户手改，脚本没有资格替用户决定丢弃。
plan_links() {
  local src="$1" top="$2" tgt="$3" rel
  while IFS= read -r -d '' rel; do
    local from="$src/$top/${rel#./}" to="$HOME/$tgt/${rel#./}"
    if [[ -e "$to" && ! -L "$to" ]]; then
      printf 'CONFLICT\t%s\t%s\n' "$to" "$from"
    else
      printf 'LINK\t%s\t%s\n' "$to" "$from"
    fi
  done < <(cd "$src/$top" && find . -type f -print0)
}

# 从 link 所在目录出发到 target 的相对路径。用 coreutils 的 realpath 而非
# 解释器——本脚本不该在运行时依赖 python。
relpath() {
  local target="$1" link_dir="$2"
  realpath --relative-to="$link_dir" "$target"
}

apply_links() {
  local pkg="$1" src="$2"
  local top; top="$(basename "$(top_dir_of "$src")")"
  local tgt="${TARGETS[$pkg]}"
  : >"$MANIFEST.tmp"
  local n=0
  while IFS=$'\t' read -r kind to from; do
    case "$kind" in
      CONFLICT)
        die "$to 已存在且不是 symlink——拒绝覆盖。
    那是真实文件（可能是你手改的），脚本不替你决定丢弃。
    处理完手工删除该文件后重跑，或用 --uninstall 先整体回滚。"
        ;;
      LINK) ;;
    esac
    local dir; dir="$(dirname "$to")"
    if [[ "$DRY_RUN" == 1 ]]; then
      log "  [dry-run] ln -s $(relpath "$from" "$dir") $to"
    else
      mkdir -p "$dir"
      ln -sfn "$(relpath "$from" "$dir")" "$to"
      printf '%s\t%s\t%s\n' "$kind" "$to" "$from" >>"$MANIFEST.tmp"
    fi
    n=$((n + 1))
  done < <(plan_links "$src" "$top" "$tgt")
  # manifest 记录本脚本建过的全部链接，uninstall 据此精确回滚。取并集去重：
  # 重复运行不膨胀，且「上一轮建的、本轮还在」只留一条。
  if [[ "$DRY_RUN" == 0 ]]; then
    sort -u -o "$MANIFEST" "$MANIFEST.tmp" "$MANIFEST" 2>/dev/null \
      || cat "$MANIFEST.tmp" >>"$MANIFEST"
  fi
  rm -f "$MANIFEST.tmp"
  log "  ✓ $pkg：$n 个文件链接 → \$HOME/$tgt"
}

uninstall() {
  [[ -f "$MANIFEST" ]] || die "找不到 manifest $MANIFEST——本脚本没铺过，或已被清理"
  local kind to from n=0
  while IFS=$'\t' read -r kind to from; do
    [[ "$kind" == LINK ]] || continue
    if [[ ! -L "$to" ]]; then
      continue                                   # 已被前一条目移除，或用户自行删除
    elif [[ "$(readlink -f "$to")" == "$(readlink -f "$from")" ]]; then
      if [[ "$DRY_RUN" == 1 ]]; then log "  [dry-run] rm $to"; else rm -f "$to"; fi
      n=$((n + 1))
    else
      # 指向被改过：可能用户手动 re-point 了，脚本无权判定该不该删。
      log "  保留（指向已变，可能是你手动改过）：$to"
    fi
  done <"$MANIFEST"
  # 清掉变空的目录（只到 TARGETS 深度，不碰上层）
  for tgt in "${TARGETS[@]}"; do
    local d="$HOME/$tgt"
    [[ "$DRY_RUN" == 1 ]] || rmdir -p "$d" 2>/dev/null || true
  done
  [[ "$DRY_RUN" == 1 ]] || rm -f "$MANIFEST"
  log "  ✓ 移除 $n 个链接"
}

# ─── 主流程 ─────────────────────────────────────────────────
main() {
  case "${1:-}" in
    --dry-run)   DRY_RUN=1 ;;
    --check)     MODE=check ;;
    --uninstall) MODE=uninstall ;;
    "")          ;;
    *)           die "未知参数：$1（支持 --dry-run / --check / --uninstall）" ;;
  esac

  if [[ "$MODE" == uninstall ]]; then
    uninstall
    return 0
  fi

  load_lock
  log "锁文件 $LOCK_FILE："
  local pkg
  for pkg in "${!TARGETS[@]}"; do
    log "  $pkg ${LOCK_VER[$pkg]:-（未锁）}"
  done
  echo >&2

  # 两段式：先把全部组件下载并校验通过，再动任何链接。
  # 半途失败不会留下「装了一半」的混合状态。
  local -a ready=()
  local ok=1
  for pkg in "${!TARGETS[@]}"; do
    [[ -n "${LOCK_VER[$pkg]:-}" ]] || continue
    if ensure_cached "$pkg" "${LOCK_VER[$pkg]}" "${LOCK_SHA[$pkg]}"; then
      ready+=("$pkg")
    else
      log "  ✗ $pkg ${LOCK_VER[$pkg]}：缓存缺失或校验不符"
      ok=0
    fi
  done
  if [[ "$ok" == 0 ]]; then
    die "有组件未就绪，未铺设任何链接（要么修锁文件，要么先发布对应 tag 的 Release）"
  fi

  mkdir -p "$(dirname "$MANIFEST")"
  for pkg in "${ready[@]}"; do
    log "$pkg ${LOCK_VER[$pkg]}"
    apply_links "$pkg" "$CACHE_ROOT/$pkg/${LOCK_VER[$pkg]}"
  done
  log
  log "完成。缓存位置：$CACHE_ROOT（多版本共存，可直接删除旧版回收）"
  [[ "$MODE" == check ]] && log "（--check 模式：只校验，不改链接）"
}

main "$@"

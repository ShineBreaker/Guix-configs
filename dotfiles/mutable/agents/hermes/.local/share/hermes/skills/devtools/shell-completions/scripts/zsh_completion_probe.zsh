#!/usr/bin/env zsh
# zsh 补全运行时探针：真 pty + ZLE 驱动 Tab，逐条断言候选。
#
# 用法:
#   zsh -f zsh_completion_probe.zsh <补全函数目录> '键入文本|期望候选[|期望候选...]' ...
# 例:
#   guix shell zsh -- zsh -f scripts/zsh_completion_probe.zsh ./completions \
#     'agenote |extract|reconcile' \
#     'agenote extract --source |opencode|zcode'
#
# 退出码: 0 全部 PASS / 1 有 FAIL / 2 用法或 zpty 不可用。

_drain() {
  emulate -L zsh
  local out="" chunk i=0
  while (( i < 40 )); do
    if zpty -r -t z chunk 2>/dev/null; then
      out+="$chunk"
    else
      sleep 0.1
      (( i++ ))
    fi
  done
  print -r -- "$out"
}

main() {
  emulate -L zsh
  if (( $# < 2 )); then
    print -u2 "用法: zsh -f $0 <补全函数目录> '键入文本|期望候选[|期望候选...]' ..."
    return 2
  fi

  local comp_dir=${1:A}
  shift
  zmodload zsh/zpty 2>/dev/null || { print -u2 "缺少 zsh/zpty 模块"; return 2 }

  local fail=0 spec typed out tok
  local -a parts expected missing

  for spec in "$@"; do
    parts=("${(@s:|:)spec}")
    typed=$parts[1]
    expected=("${parts[2,-1]}")

    zpty -d z 2>/dev/null
    zpty -b z zsh -f -i 2>/dev/null || { print -u2 "启动 pty zsh 失败"; return 2 }
    # COLUMNS 放宽：窄 pty 会分栏/截断候选，看起来像没有候选
    zpty -w z "PROMPT=''; RPROMPT=''; setopt no_beep; export COLUMNS=200 LINES=60"
    zpty -w z "fpath=($comp_dir \$fpath)"
    zpty -w z "autoload -U compinit; compinit -u -d /tmp/.zcd-probe.$$"
    sleep 1.2
    _drain >/dev/null

    # 文本与 Tab 分开写各留窗口；一次性写完再立刻读会吞掉候选
    zpty -w -n z "$typed"
    sleep 0.3
    zpty -w -n z $'\t'
    sleep 2
    out=$(_drain)

    missing=()
    for tok in "$expected[@]"; do
      [[ $out == *"$tok"* ]] || missing+=("$tok")
    done

    if (( ${#missing} == 0 )); then
      print -- "PASS  [$typed]"
    else
      fail=1
      print -- "FAIL  [$typed]  缺: ${(j:, :)missing}"
      print -- "      raw: ${(V)out}"
    fi
    zpty -d z 2>/dev/null
  done

  if (( fail == 0 )); then
    print -- "zsh 补全探针: 全部通过"
  else
    print -u2 -- "zsh 补全探针: 存在失败用例"
  fi
  return $fail
}

main "$@"

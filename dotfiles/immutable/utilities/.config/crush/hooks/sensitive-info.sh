#!/usr/bin/env bash
set -euo pipefail

TOOL="${CRUSH_TOOL_NAME:-}"
FILE="${CRUSH_TOOL_INPUT_FILE_PATH:-}"

# 只检测写入操作
if [[ "$TOOL" != "write" && "$TOOL" != "edit" && "$TOOL" != "multiedit" ]]; then
  echo '{}'
  exit 0
fi

# 从 stdin 获取完整输入 JSON，提取内容
INPUT=$(cat)
CONTENT=""

# write: 检查 content
# edit/multiedit: 检查 new_string（新增/修改的部分）
case "$TOOL" in
  write)
    CONTENT=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('content',''), end='')" 2>/dev/null || true)
    ;;
  edit|multiedit)
    # 对 multiedit，检查所有 edits 中的 new_string
    CONTENT=$(echo "$INPUT" | python3 -c "
import sys, json
inp = json.load(sys.stdin)
tool_input = inp.get('tool_input', {})
if 'new_string' in tool_input:
    print(tool_input.get('new_string', ''), end='')
elif 'edits' in tool_input:
    for e in tool_input['edits']:
        print(e.get('new_string', ''), end='')
" 2>/dev/null || true)
    ;;
esac

if [[ -z "$CONTENT" ]]; then
  echo '{}'
  exit 0
fi

# 将内容写入临时文件以便 grep 检测
TMPFILE=$(mktemp)
trap "rm -f '$TMPFILE'" EXIT
printf '%s' "$CONTENT" > "$TMPFILE"

# 检测 API key 和密钥模式
FOUND=""

# OpenAI/DeepSeek/Hyper 等的 sk- 格式 key
if grep -qiE 'sk-[a-zA-Z0-9]{20,}' "$TMPFILE"; then
  FOUND="检测到疑似 API key（sk-... 格式）"
fi

# 明文密码字段（避免引号冲突，用简单模式）
if grep -qiE '(password|passwd|secret|token|api[_-]?key)[[:space:]]*[:=][[:space:]]*[\"\047][^\"\047[:space:]]{8,}[\"\047]' "$TMPFILE"; then
  FOUND="${FOUND}; 检测到明文密码/secret/token 字段"
fi

# SSH private key
if grep -qE -e '-----BEGIN (RSA |EC |DSA |OPENSSH )?PRIVATE KEY-----' "$TMPFILE"; then
  FOUND="${FOUND}; 检测到 SSH 私钥"
fi

# AWS/Azure/GCP access key
if grep -qiE 'AKIA[0-9A-Z]{16}' "$TMPFILE"; then
  FOUND="${FOUND}; 检测到疑似 AWS access key"
fi

if grep -qiE 'ghp_[a-zA-Z0-9]{36}' "$TMPFILE"; then
  FOUND="${FOUND}; 检测到疑似 GitHub personal access token"
fi

if [[ -n "$FOUND" ]]; then
  # 去掉前导分号和空格
  FOUND="${FOUND#; }"
  echo "⚠️ $FOUND" >&2
  echo "写入文件时检测到敏感信息。如果确认无风险，请手动确认后重试。" >&2
  exit 49  # halt 整个 turn，让用户处理
fi

echo '{}'

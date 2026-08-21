# Parser Bugs Found During 2026-07-26 Audit

Three bugs in `_parse_json_lenient` and `check_cross_window_errors` that produced false RED signals during the agent-config-metabolism weekly audit.

## Bug 1: Block comment regex eats `/*` inside JSON strings

**Symptom.** `check_json_parseable` reports 99 broken JSON files; ground truth is 0.

**Root cause.** `re.sub(r'/\*.*?\*/', '', text, flags=re.DOTALL)` is not string-aware. For a tsconfig.json with `"paths": {"@/*": ["./src/*"]}`, the regex matches from the first `/*` to the first `*/` — both inside a JSON string — and deletes them. The result is invalid JSON.

**Fix.** Implement string-aware block comment stripping (character-by-character state machine):

```python
out_chars = []
i = 0
in_str = False
esc = False
while i < len(text):
    ch = text[i]
    if esc:
        out_chars.append(ch)
        esc = False
    elif ch == "\\" and in_str:
        out_chars.append(ch)
        esc = True
    elif ch == '"':
        in_str = not in_str
        out_chars.append(ch)
    elif not in_str and ch == "/" and i + 1 < len(text) and text[i + 1] == "*":
        i += 2
        while i < len(text) - 1:
            if text[i] == "*" and text[i + 1] == "/":
                i += 2
                break
            i += 1
        else:
            i = len(text)
        continue
    else:
        out_chars.append(ch)
    i += 1
text_no_block = "".join(out_chars)
```

**Verification.** After fix, `hermes-agent/web/tsconfig.app.json` (which has `"paths": {"@/*": [...]}`) parses correctly.

## Bug 2: Lenient parser must not run before standard parser

**Symptom.** Valid JSON files with `https://` URLs in string values fail the lenient parser.

**Root cause.** `_parse_json_lenient` was called on every file. The `//` line-comment stripper sees `https://` as a line comment start and truncates the rest of the line. Result: valid JSON becomes invalid.

**Fix.** Try `json.loads(text)` first; only fall back to `_parse_json_lenient` when standard parsing fails:

```python
try:
    json.loads(text)
    continue  # Valid standard JSON — done
except (json.JSONDecodeError, ValueError):
    pass
# Standard parsing failed — try lenient (JSONC) parser
ok, err = _parse_json_lenient(text)
```

## Bug 3: Trailing comma regex `r",(\s*[\\]}])"` is broken

**Symptom.** JSONC files with trailing commas (`,}` or `,]`) still fail parsing.

**Root cause.** The regex `r",(\s*[\\]}])"` has a double-backslash in the character class `[\\]}]`. In a Python raw string, `\\` matches a literal backslash, so the character class matches `\`, `]`, or `}` — NOT `]` or `}`. The regex only strips `,\]` and `,\}` (and `,\\`) — it never matches `,]` or `,}`.

**Fix.** Use `r",(\s*[]}])"` instead.

**Verification.** After fix, `lsp/node_modules/yaml-language-server/tsconfig.esm.json` (which has `"outDir": "./lib/esm",` with trailing comma) parses correctly.

## Bug 4: Error count threshold compared against total lines, not unique signatures

**Symptom.** `check_cross_window_errors` reports 291 errors (threshold 5) when there are only 23 unique signatures, most from a single repeating Weixin poll failure.

**Root cause.** The status check was `err_count <= max_per` (total lines) instead of `n_unique <= max_per` (unique signatures).

**Fix.** Change to `n_unique <= max_per` and update the detail format to show both numbers: `errors {n_unique} unique sigs (total {err_count})`.

## Bug 5: Traceback blocks counted per-line instead of per-block

**Symptom.** A single Traceback with 20 frame lines was counted as 20 errors.

**Root cause.** The main scan loop incremented `err_count` for every line containing "Traceback", including indented frame lines within the same block.

**Fix.** Track which traceback blocks have been seen (`tb_offsets_seen` set) and only count the first line of each block.
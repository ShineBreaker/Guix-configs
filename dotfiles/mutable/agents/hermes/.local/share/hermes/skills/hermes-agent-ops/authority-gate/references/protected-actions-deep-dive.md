# 与机器硬拦截的分工（anchors / gate-core / pi-gate）

本 skill 是软 gate：靠 agent 自律加 `clarify()` 询问。它是最后一道防线，不是第一道。

## 三层防线

| 层 | 机制 | 性质 | 适用场景 |
|----|------|------|----------|
| 机器硬拦截 | `anchors.json`（两级）加 `gate-core.sh` 加各端适配器（Pi-Gate TS / Crush bash hooks / ZCode bash hooks / Hermes gate 插件） | 命令级拦截，agent 绕不过 | 已能写成确定 pattern 的命令与路径 |
| 本 skill 软 gate | P 清单、三条自问、`clarify()` | agent 自律，可能漏 | 清单外的新形态、需要上下文判断的边界 |
| 人工总开关 | `/run/agent-gate.off` | 暂停全部护栏 | 仅用户可创建与删除（需 sudo，对 agent 恒冻） |

一条规则如果能写成确定的命令或路径 pattern，就进 `anchors.json` 的
`frozen_commands` / `frozen_paths` 让机器拦；只有需要上下文判断时（比如这个
`trash` 的目标是不是用户自己的临时目录）才留给本 skill。发现某条 P 规则已经能固化成
pattern 时，建议用户把它写进 anchors，别只靠 agent 记住。

## 护栏暂停期间

`/run/agent-gate.off` 存在时各端全部放行，仅附提示。此时 agent 照旧执行软 gate：
暂停的是机器拦截，不是用户授权。放行了 protected action 仍在回复中说明清楚。

agent 不得代用户创建或删除该开关，不得主动要求用户关闭护栏。

## 后台会话的写入限制

后台与 curator 会话对 user-owned skill（`created_by=None`）的 `skill_manage` 写入
会被拒绝，需 `hermes curator adopt <name>`。连续两次相同拒绝即停手，把建议改动写进
回复交前台会话落地，不要反复重试。

## 自检

```bash
python3 scripts/detect-protected-action.py "<command>"   # rule-based 命中检查
python3 scripts/verify-authority-gate.py                 # 本 skill 自校验
```

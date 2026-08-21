# 意图判别:用户说 "minimax / MiniMax" 时到底指什么

本机 hermes 的对话上下文里 "minimax" 这个词有**至少三个潜在指代**,混在一起就会做错事。踩过一次(2026-06-23,误判为"换视觉模型" → 走 2 次 clarify 才发现是 TTS),记录如下。

## 三种指代

| 用户原话 | 实际可能 | 判别信号 |
|---|---|---|
| "换 minimax 的" / "用 minimax 那个" | **A. MiniMax 厂商**(深圳那家,做 LLM + TTS 的) | 用户在改 **API 接入层**时提到("用 minimax 的 API" "minimax 有个 X 接口") |
| "minimax-cn 的 MiniMax-M3" / "用那个 minimax 模型" | **B. 对端模型 `MiniMax-M3`**(hermes `providers.minimax-cn.models.MiniMax-M3`) | 用户在改 **对话/视觉模型 routing** 时提到 |
| "MiniMax-M3" / "m3 模型" | **C. 同 B,但更明确** | 单独出现 M3 / M3 引用 |

## 判别三步法(做之前先跑)

1. **看上下文**。用户上一句在聊什么?
   - 在聊视频/渲染/教程输出 → 几乎肯定是 **TTS**(minimax 有云端语音 API)
   - 在聊 provider/model/routing/auxiliary → **A 还是 B 看具体词**
2. **看动词**。"换 minimax 的" + 视频上下文 → 99% 是 TTS 引擎; "换 minimax 的" + 模型上下文 → 99% 是切到 MiniMax-M3
3. **看"那个"指向**。"那个 minimax" = 通常是上一轮已经讨论过的具体指代,需要回看上面 5 轮

## 走错代价

- 误把"换 minimax 的"理解为"换视觉模型" → 调 `clarify` 2 次浪费 1-2 轮
- 凭印象给 MiniMax TTS 编 endpoint / 鉴权方式 → 直接踩"凭印象写 endpoint" 的硬规则(见 voiceover-and-captions.md 坑 3,此坑已解除)

## 现在已确认的事实(2026-06-23 实测)

- `~/.local/share/hermes/.env` 里 `MINIMAX_CN_API_KEY` 存在,长度 125 字符,有效
- `providers.minimax-cn.models.MiniMax-M3` 是 **对话主模型**(anthropic-messages 兼容)
- 厂商 `https://api-bj.minimaxi.com/v1/t2a_v2` 是 **TTS 接口**,Bearer 鉴权
- 这两个 **不是同一个东西**:对话用 LLM API(`v1/text/chatcompletion_v2` 之类),TTS 用 T2A API(`v1/t2a_v2`)。用户在视频工作流里说的"minimax" = **TTS**。

## 操作清单

如果下次用户再说 "换 minimax 的 / 用 minimax":

- [ ] 跑上面"判别三步法"
- [ ] 如果是 TTS(高频):直接调 `python3 scripts/minimax-tts.py`,不用先 clarify
- [ ] 如果不确定:**一次** clarify,给出具体选项,不要泛问"您想换什么"——这会被打回

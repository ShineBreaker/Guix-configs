# I-CHIP 小键盘 ↔ 笔记本 kanata 对位基线

本用户外接小键盘（I-CHIP GamingKeyboard，用厂商网页驱动改键）与笔记本内置键盘（kanata 接管，源在 Guix-configs 的 `source/config.org`）要保持同一套手指记忆。再次核对或改动前先读本文；**键值以 `source/config.org` 的 kanata 块为准**，本文给对位模型与已确认的例外键。

## 对位模型（经用户确认）

- **字母/符号区逐格同位**：小键盘自上而下 4 行 ↔ 笔记本 QWERTY / ASDF / ZXCV / 底行（行首对行首）。
- **功能键同名对应**：
  - 左上角 Esc/MT 格 ↔ 物理 Tab 键（单击 Tab，按住 ≥150ms 为 Esc）；
  - 行首 CTRL 格 ↔ 物理 CapsLock（base 出 Ctrl，Fn 层出 CapsLock）；
  - 2u Backspace 格 ↔ 物理 Backspace 键（**不是** `[` `]`）；
  - 2u ENTER 格 ↔ 物理 Enter 键；
  - FN 格（底行中）↔ 物理 RAlt（按住激活 fn 层）；
  - 底行左三 ↔ 物理 L_Ctrl / L_Win / L_Alt。
- 空格位不映射（图上长键上的小横杠＝空格的显示形式，不是减号）。

## Fn 层基线值

| 物理键 | Fn 层输出 |
|---|---|
| Tab | Esc |
| Q W E R T Y U I O P | 1..0 |
| A S D F G | F1..F5 |
| H J K L | `[` `]` `;` `'` |
| Z X C V B N M | F6..F12 |
| Backspace | `-` |
| Enter | `\` |
| L_Ctrl / L_Win / L_Alt | L_Alt / `` ` `` / L_Ctrl（对调） |
| 其余 | 透传 |

## 有意不映射

- 背光类（开关/亮度±/速度±）：小键盘固件专属功能，`defsrc` 无对应键——如实告知不可行，不要糊假映射。
- 方向键、PgUp / PgDn / Del：笔记本同名键自理，不进 `defsrc`。
- 小键盘 Fn 层的静音 / 音量：笔记本侧无自然落点，待用户决定是否挑键补。

## 复核时留意

- 正文映射表与当前图冲突时，以**图 + 用户确认**为准，并同步改正文（历史文案如「两键同映射」类表述可能已过时）。查核规则：Enter 位的 Fn 值应为 `\`，Backspace 位才是 `-`；若发现 Enter 位是 `-`，是漂移，改回。
- Fn 层截图里 FN 键呈红色高亮属显示样式，非键位改动。
- 用户会在图例有歧义时直接澄清（MT 面板截图、空格显示说明）；把歧义点整理成清单问，别死磕读图。

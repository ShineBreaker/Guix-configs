---
name: gui-demo-recording
version: 1.0
author: hermes
description: 用 Xvfb 隔离实录 GUI 演示视频并生成可配音字幕。触发：录软件演示/宣传片、自动化 GUI 操作并录屏。
category: desktop
---

# GUI 演示视频录制（Xvfb 隔离实录）

## When to Use

- 给某个已安装的 GUI 应用录操作演示/介绍视频（含自动化按键 + 后期字幕对轴）。
- 需要在不干扰用户当前桌面的前提下自动化 GUI 操作并录屏/截图。
- 用户要「能直接拿去配音」的字幕文件（精确对轴的 SRT/ASS）。

在独立 Xvfb 显示服务器里跑目标应用，用 XTEST 脚本驱动按键，ffmpeg x11grab 分镜录制。**绝不驱动或录制用户正在使用的真实桌面**——既避免干扰用户，也避开真实桌面不可控的焦点与窗口布局。

## 硬规则（每次录制都适用）

- **屏幕状态协议**：用户不在电脑前时，动手前先 `brightnessctl -d intel_backlight set 1` 把屏幕压到最低；凡误投到真实桌面的窗口（`niri msg windows` 出现用户原有的 App ID 之外的条目）必须 `niri msg action close-window --id <ID>` 关掉；收尾时再核对一遍亮度值与窗口清单，确保屏幕是灭的。
- **fixture 隔离**：演示用文件放 /tmp 下专用目录/仓库，由脚本一键重建（rm -rf + 重建），绝不打开用户真实项目；每轮录制前重建一次。
- **录一镜验一镜**：每段录完立即 `ffprobe` 时长 + 按 mark 时刻抽 4-6 帧 vision 验收，不合格马上重录；不要攒到最后一起看。
- **字幕轴不靠估算**：每个关键动作前后 `mark "标签"` 打绝对时间戳，SHOT_START/SHOT_END 兜底，镜长用 ffprobe 拿精确值；用户要求字幕可直接拿去配音，轴误差必须 < 0.3s。
- 先写分镜清单（STORYBOARD.md：每镜的目标时长/展示功能/配音要点），fixture 与驱动脚本按镜编号命名。

## 环境搭建（Guix/Wayland 主机）

1. 临时工具一次性拉齐：`guix shell xorg-server xdotool xautomation -- ./run-shot.sh ...`。Xvfb 在 xorg-server 包里（没有独立的 xvfb 包）；键盘注入用 xautomation 的 `xte`。
2. 目标应用是 Guix wrapper（如 emacs 的 guile wrapper）时，**直调真实二进制并手工补环境**：`unset WAYLAND_DISPLAY`、`DISPLAY=:$N`、EMACSLOADPATH / EMACSNATIVELOADPATH / TREE_SITTER_GRAMMAR_PATH 等指向 profile。wrapper 继承的 WAYLAND_DISPLAY 会让 pgtk 应用开到用户真实桌面上，Xvfb 抓到的是黑帧。
3. Xvfb：`Xvfb :120 -screen 0 1920x1080x24 -nolisten tcp`；录制 `ffmpeg -f x11grab -video_size 1920x1080 -framerate 30 -i :120 -c:v libx264 -preset veryfast -crf 20 -pix_fmt yuv420p out.mp4`；停止必须 `kill -INT`（让 ffmpeg 正常收尾写 moov，kill -9 产出损坏文件）。
4. 窗口摆放：`xdotool search --name` 找主窗口 → `windowsize <W> 1920 1080` + `windowmove <W> 0 0` 铺满画布 → `windowfocus --sync <W>`。应用的 frame 先用 --eval 拉大（如 emacs 的 `set-frame-size` 215x54），再 xdotool 微调到位。
5. 抓到的 mp4 只有几 KB = 画面全黑 = 应用没起来或开到了别的显示；先确认 Xvfb 内窗口列表存在再开始录。

## 按键驱动

- 用 xte（XTEST 真实注入）。`xdotool key --window` 走 XSendEvent，对 Emacs 等应用不可靠，键会被吞。
- 组合键范式：`xte "keydown Control_L" "usleep 100000" "key x" "usleep 100000" "keyup Control_L"`；大写直接 `key T`；常用键名 Return / Escape / space / grave（反引号）/ Left，生僻键先查 man 页确认。
- 节奏：前缀键（C-x / C-c）按下后等弹窗真正出现再按后续键（实测 ≥1.2s），弹窗内后续键间隔 0.6-0.8s。**键盘序列失败优先怀疑间隔太短**，逐键加 wait 重试，而不是换注入方式。

## 被录应用的「录制模式」补丁

录真实用户配置时，用一个补丁 el 在用户 init 之前 `--load` 注入（advice-add 对未定义符号合法，main.el 定义后 advice 依然生效）：

- 拦 eglot-ensure：LSP 连接（如 pylsp）会把 buffer 弄脏成 unsaved，非 LSP 特写镜头必须关掉。
- 拦失焦自动保存：Xvfb 无窗口管理器，frame-focus-state 恒 nil，「失焦自动保存」类 hook 会进入保存循环，弹出 Save prompt 卡死整个镜头。
- 拦 apheleia 类保存后异步格式化：它让 buffer 永远处于 modified，同样触发保存询问。
- `warning-minimum-level :error` 静音无害 warning 弹窗。

**已知未解**：录制的 standalone emacs 会弹「Unable to start the Emacs server」（socket 被用户真实 daemon 占用）的 warning，fset / advice server-mode 与 server-start 均未能拦住；它出现在画面底部约三行，接受后期裁剪，录前先抽帧确认底部区域。

**lock 文件陷阱**：应用曾被 kill -9 会留下 `.#file` 符号链接锁，下次打开同名文件会弹保存询问；不要逐个清锁，直接重建整个 fixture 目录。

## 后期对轴与交付

- 镜内动作时刻 = mark 日志绝对时间戳 − SHOT_START；镜长用 ffprobe 精确读取。
- 验收抽帧用裁剪：`ffmpeg -ss <t> -i shot.mp4 -frames:v 1 -vf crop=<W>:<H>:<X>:<Y>` 只截关注区域（minibuffer / modeline / 底栏）再逐帧 vision 读内容，比全屏截图定位问题快得多。
- 中文 TTS 实测语速 ~6.6 字/秒；每句字幕字数 ÷ 6.6 ≈ 该句最短停留时长，短于画面时长说明镜头可缩短或加内容。
- 交付物：成片 mp4 + `demo.srt`（通用）+ `demo.ass`（带样式，可直接烧录）+ `narration.md`（逐句配音稿，标注入镜时间与字数）。

## 模板

`templates/run-shot.sh`（一体式：Xvfb + 应用 + 录制 + 驱动 + 清理）、`templates/lib.sh`（mark / key / ctrl / type / wait 工具集，driver 脚本直接用）、`templates/demo-inject.el`（录制模式补丁骨架）。复制到项目 work/ 目录，改「应用环境」段即可换目标应用。

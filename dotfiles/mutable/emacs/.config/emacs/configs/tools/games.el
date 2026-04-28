;;; games.el --- 游戏 -*- lexical-binding: t; -*-

;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

;;; Commentary:
;; Emacs 内置游戏与外部游戏的配置入口。
;;
;; 可用游戏列表：
;; - tetris   - 俄罗斯方块（内置）
;; - snake    - 贪吃蛇（内置）
;; - gomoku   - 五子棋（内置）
;; - pong     - 乒乓球（内置）
;; - bubbles  - 泡泡射手（内置）
;; - 2048     - 2048 游戏（外部）
;;
;; 快捷键入口：`C-c a g`
;; Troubleshooting：
;; - 游戏无法启动 → 检查是否为内置游戏或已安装外部包
;; - 游戏按键异常 → 先确认当前终端/图形环境是否吞掉方向键

;;; Code:

;; 2048 游戏（外部包）
(use-package 2048-game
  :defer t
  :commands 2048-game)

(provide 'games)
;;; games.el ends here

;;; modules/10-performance.lisp — 运行时性能调优（GC 阈值）
;;;
;;; 依赖：utils（vs$）；无下游依赖。数字前缀取 10，加载在全部功能模块
;;; 之前——让后续模块的加载分配也落在调优后的阈值内。
;;;
;;; SBCL genCGC 的 GC 是 stop-the-world：编辑器每键 cons（modeline 重绘、
;;; buffer 编辑、渲染），GC 停顿直接表现为按键卡顿。两个可控旋钮（都是
;;; 函数不是特殊变量，setf 走宏展开，故用 eval 构造）：
;;;
;;; 1. SB-EXT:BYTES-CONSED-BETWEEN-GCS —— **gen0（nursery）的真实阈值**。
;;;    文档："On GENCGC platforms this is the nursery size, and defaults
;;;    to 5% of dynamic space size"（本机 dynamic space 3GB → 默认
;;;    153.6MB）。这是「nursery 分配多少字节后触发 minor GC」的唯一入口。
;;;    ⚠ GENERATION-BYTES-CONSED-BETWEEN-GCS 的 **0 号槽对 nursery 无效**
;;;    （同文档 "meaningless for generation 0"），旧写法设的正是那个槽——
;;;    是 no-op（2026-09-11 实测：设 64MB 后读回 64MB 但 GC 行为不变，
;;;    真正的 nursery 阈值仍是 bytes-consed-between-gcs 的 153.6MB）。
;;;    0 代设 256MB：minor GC 实测极快（320MB 分配周期 GC 总计 0.6ms，
;;;    见下方实测），nursery 翻倍把 GC 次数减半，单次增幅可忽略。
;;;
;;; 2. SB-EXT:GENERATION-BYTES-CONSED-BETWEEN-GCS 的 1/2 号槽 —— 老年代
;;;    晋升阈值，默认 30.7MB（dynamic space 的 1%）。编辑器长期运行积累
;;;    大量永生对象（buffer / overlay / 包符号），30MB 老年代很快填满 →
;;;    major GC（扫描整代，停顿远长于 minor）频繁触发。提到 128MB 把
;;;    major GC 间隔拉长约 4 倍；代价是单次多扫 ~100MB（毫秒级）。
;;;
;;; 实测基线（2026-09-11，SBCL 2.6.4）：nursery=153.6MB 下分配 320MB
;;; 短命垃圾，*GC-RUN-TIME* 累计仅 0.6ms —— minor GC 不是卡顿源，
;;; 真正的停顿来自 major GC，故「调 gen1/gen2」比「调 gen0」更对症。

(in-package :lem-user)

;; gen0 / nursery：真实入口（函数名位置 setf 需 eval 展开）
(let ((fn (vs$ :sb-ext "BYTES-CONSED-BETWEEN-GCS")))
  (if (and fn (fboundp fn))
      (eval `(setf (,fn) ,(* 256 1024 1024)))
      ;; 旧镜像可能只暴露特殊变量形式
      (let ((var (vs$ :sb-ext "*BYTES-CONSED-BETWEEN-GCS*")))
        (if (and var (boundp var))
            (setf (symbol-value var) (* 256 1024 1024))
            (vs-warn :gc-nursery-threshold-missing)))))

;; gen1 / gen2：老年代晋升阈值
(let ((fn (vs$ :sb-ext "GENERATION-BYTES-CONSED-BETWEEN-GCS")))
  (if (and fn (fboundp fn))
      (progn
        (eval `(setf (,fn 1) ,(* 128 1024 1024)))
        (eval `(setf (,fn 2) ,(* 128 1024 1024))))
      (vs-warn :gc-oldgen-threshold-missing)))

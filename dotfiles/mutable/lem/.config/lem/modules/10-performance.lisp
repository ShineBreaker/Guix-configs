;;; modules/10-performance.lisp — 运行时性能调优（GC 阈值）
;;;
;;; 依赖：utils（vs$）；无下游依赖。数字前缀取 10，加载在全部功能模块
;;; 之前——让后续模块的加载分配也落在调优后的阈值内。
;;;
;;; SBCL genCGC 的 GC 是 stop-the-world：编辑器每键 cons（modeline 重绘、
;;; buffer 编辑、渲染），而镜像默认每代阈值仅 ~10MB——实测 100MB 分配
;;; 负载触发 8 次 GC / 92-128ms。把 0 代（nursery）阈值提到 64MB 后同
;;; 负载 0 次 GC。卡顿频率显著下降；代价是 GC 触发时单次略长、峰值
;;; 内存驻留最多 +64MB 级，现代机器无感。
;;;
;;; 镜像注意事项：SB-EXT 的 *BYTES-CONSED-BETWEEN-GCS* 特殊变量在
;;; nightly 镜像内不存在（探针实证），可控入口是每代 accessor
;;; GENERATION-BYTES-CONSED-BETWEEN-GCS；其 setf 无独立函数符号，
;;; 必须 eval 走宏展开（vs-setglobal 的 symbol-value 路径写不动它）。

(in-package :lem-user)

(let ((fn (vs$ :sb-ext "GENERATION-BYTES-CONSED-BETWEEN-GCS")))
  (if (and fn (fboundp fn))
      (eval `(setf (,fn 0) ,(* 64 1024 1024)))
      (vs-warn (list :gc-threshold-tuning fn))))

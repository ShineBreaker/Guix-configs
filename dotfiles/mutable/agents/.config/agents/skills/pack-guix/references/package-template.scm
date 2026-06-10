;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: MIT

;;; pack-guix — Guix Package 定义模板
;;; 根据构建系统选择对应模板

;;; ============================================================
;;; 模板 1：GNU Build System（autoconf/automake）
;;; ============================================================
(define-public %name%
  (package
    (name "%name%")
    (version "%version%")
    (source (origin
              (method git-fetch)
              (uri (git-reference
                    (url "%repo-url%")
                    (commit (string-append "v" version))))
              (file-name (git-file-name name version))
              (sha256 (base32 "%sha256-hash%"))))
    (build-system gnu-build-system)
    (inputs (list %inputs%))
    (native-inputs (list pkg-config))
    (home-page "%home-page%")
    (synopsis "%synopsis%")
    (description "%description%")
    (license %license%)))

;;; ============================================================
;;; 模板 2：CMake Build System
;;; ============================================================
(define-public %name%
  (package
    (name "%name%")
    (version "%version%")
    (source (origin
              (method git-fetch)
              (uri (git-reference
                    (url "%repo-url%")
                    (commit (string-append "v" version))))
              (file-name (git-file-name name version))
              (sha256 (base32 "%sha256-hash%"))))
    (build-system cmake-build-system)
    (inputs (list %inputs%))
    (home-page "%home-page%")
    (synopsis "%synopsis%")
    (description "%description%")
    (license %license%)))

;;; ============================================================
;;; 模板 3：Trivial Build System（预编译 binary）
;;; ============================================================
(define-public %name%
  (package
    (name "%name%")
    (version "%version%")
    (source (origin
              (method url-fetch)
              (uri "%binary-url%")
              (sha256 (base32 "%sha256-hash%"))))
    (build-system trivial-build-system)
    (inputs (list bash coreutils glibc))
    (arguments
     (list
      #:modules '((guix build utils))
      #:builder
      (begin
        (use-modules (guix build utils))
        (let* ((out (assoc-ref %outputs "out"))
               (src (assoc-ref %build-inputs "source"))
               (bin-dir (string-append out "/bin"))
               (lib-dir (string-append out "/lib/%name%")))
          ;; 创建输出目录
          (mkdir-p bin-dir)
          (mkdir-p lib-dir)
          ;; 解压 binary
          (invoke "tar" "xzf" src "-C" lib-dir "--strip-components=1")
          ;; 复制 binary 到 bin
          (copy-file (string-append lib-dir "/%name%")
                     (string-append bin-dir "/%name%"))
          (chmod (string-append bin-dir "/%name%") #o755)
          ;; patchelf 修复动态链接器
          (invoke "patchelf"
                  "--set-interpreter"
                  (string-append (assoc-ref %build-inputs "glibc")
                                 "/lib/ld-linux-x86-64.so.2")
                  (string-append bin-dir "/%name%"))
          #t))))
    (home-page "%home-page%")
    (synopsis "%synopsis%")
    (description "%description%")
    (license %license%)
    (supported-systems '("x86_64-linux"))))

;;; ============================================================
;;; 模板 4：Binary + Wrapper Script 模式
;;; （适用于无法 patchelf 的预编译 binary）
;;; ============================================================
(define-public %name%
  (package
    (name "%name%")
    (version "%version%")
    (source (origin
              (method url-fetch)
              (uri "%binary-url%")
              (sha256 (base32 "%sha256-hash%"))))
    (build-system trivial-build-system)
    (inputs (list bash coreutils glibc))
    (arguments
     (list
      #:modules '((guix build utils))
      #:builder
      (begin
        (use-modules (guix build utils))
        (let* ((out (assoc-ref %outputs "out"))
               (src (assoc-ref %build-inputs "source"))
               (bin-dir (string-append out "/bin"))
               (libexec-dir (string-append out "/libexec/%name%")))
          ;; 创建目录
          (mkdir-p bin-dir)
          (mkdir-p libexec-dir)
          ;; 解压到 libexec
          (invoke "tar" "xzf" src "-C" libexec-dir "--strip-components=1")
          ;; 创建 wrapper 脚本
          (call-with-output-file (string-append bin-dir "/%name%")
            (lambda (port)
              (format port "#!~a~%"
                      (string-append (assoc-ref %build-inputs "bash") "/bin/bash"))
              (format port "exec ~a/libexec/%name%/%name% \"$@\"~%" out)))
          (chmod (string-append bin-dir "/%name%") #o755)
          #t))))
    (home-page "%home-page%")
    (synopsis "%synopsis%")
    (description "%description%")
    (license %license%)
    (supported-systems '("x86_64-linux"))))

;;; ============================================================
;;; 模板 5：Guix channel 集成（自定义频道中的包）
;;; ============================================================
(define-module (%channel-name% packages %category%)
  #:use-module (guix packages)
  #:use-module (guix download)
  #:use-module (guix git-download)
  #:use-module (guix build-system gnu)
  #:use-module (guix licenses))

(define-public %name%
  (package
    (inherit %base-package%)
    ;; 自定义字段
    ))

;;; ============================================================
;;; 占位符说明
;;; ============================================================
;;; %name%           — 包名（小写，连字符分隔）
;;; %version%        — 版本号
;;; %repo-url%       — 源码仓库 URL
;;; %binary-url%     — 预编译 binary 下载 URL
;;; %sha256-hash%    — Guix base32 格式的 hash
;;; %inputs%         — 依赖列表，如：zlib openssl curl
;;; %home-page%      — 项目主页
;;; %synopsis%       — 一行简介
;;; %description%    — 详细描述
;;; %license%        — 许可证，如：license:gpl3+

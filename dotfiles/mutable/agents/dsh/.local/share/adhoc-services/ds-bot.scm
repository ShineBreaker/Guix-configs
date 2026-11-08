;; ds-bot：宿主 shepherd 拉起，经 distrobox 进 my-distrobox 跑 DS Bot 自带的
;; 独立 DSH host。adhoc-services 按文件名加载，服务名须与文件名一致。
;;
;; DS Bot 是 Fei2411/DS-Bot 的独立 AppImage（v0.3.1，/data/Programs/ds-bot），
;; 自带一套 pinned 的 DeepSeek Harness，与主系统 DSH 零共享——它替代的是
;; hermes gateway 的位置（常驻于容器内的 agent 服务）。
;;
;; 为什么直接起 host.mjs 而不是 AppImage 本体：Linux 上 DS Bot 的 host 跑在
;; plain Node 里（resources/app/src/host.mjs），Electron 壳只负责 spawn 它并
;; 把 loopback 端口上的 web server 显示到窗口。所以容器内不需要 X/Wayland，
;; 起 host.mjs 就是完整的服务，浏览器/手机端连同一个端口即可。
;;
;; 启动命令分三层，前两层与 hermes-gateway 同源（容器与宿主的环境错位）：
;;
;; 1. 外层等宿主 /etc/resolv.conf 就位。该文件由 tailscale 动态重建，开机先删
;;    后写，中间有空窗；crun 拉起容器要 stat 它，撞上窗口就报 cannot stat
;;    /etc/resolv.conf，连续失败后 shepherd 会把服务标记为禁用，之后不再自起。
;;    最多等 60 秒，等不到也照常往下走。
;; 2. 内层进容器后 unset SSL_CERT_FILE，再按容器发行版的证书路径重新指定。
;;    shepherd 继承宿主的登录环境，该变量指到 ~/.guix-home/profile 下的 store
;;    证书路径，容器里没有对应的 store 对象，Node 建 TLS 上下文时会抛
;;    FileNotFoundError。
;; 3. 进容器后先按端口清掉上一次的 host.mjs 再起新的。shepherd 的
;;    make-kill-destructor 只杀它记录的子进程（宿主侧那条 sh），容器内的 node
;;    是孙子进程，杀不到——于是 herd restart 会留下旧 node 占着 3081，新实例
;;    webserver EADDRINUSE 起不来，连锁让 llm 等服务 inactive，ds-bot 整体进入
;;    只读（2026-11-08 实录）。
;;    用 fuser -k 按端口杀，不用 pkill -f：本进程自己的命令行里就含着
;;    primary-runtime/.../node src/host.mjs（最后的 exec 段），pkill 的模式
;;    会匹配到自己，直接把承载它的 sh 杀掉，shepherd 记到退出码 143。
;; 4. 进容器用 podman exec 而不是 distrobox enter：my-distrobox 的 user
;;    namespace 没走 keep-id，容器内 uid 0 才映射到宿主 uid 100000（数据目录
;;    现有属主），而 distrobox enter 以宿主 uid 1000 进容器会落到容器 uid
;;    1000、宿主 101000，写 /data/ds-bot/data 直接 EACCES。命令全用绝对路径，
;;    不依赖 distrobox 注入的那套环境。
;;
;; 环境变量在容器内显式 export，不依赖继承：
;;    - DSH_HOME 指到 /data/ds-bot/data。容器内 /home/brokenshine 与宿主 home
;;      是不同的 btrfs subvolume（/SYSTEM/Guix/@data vs /DATA/Home/Guix），两者
;;      天然隔离；只有 /data（/DATA/Share）是跨容器/宿主的共享面，数据必须落在
;;      这里才能两边可见。
;;    - node 用 AppImage 内置的 primary-runtime/dependencies/node/bin/node，
;;      不跟随容器系统 node 的版本演进。
;;    - DS_BOT_USER_DSH_HOME 指到一个不存在的路径，让 host 不去找用户自己的
;;      DSH 团队做首次运行导入。
;;
;; 端口 3081：容器是 host 网络模式，容器内 127.0.0.1:3081 即宿主同一地址；
;; 主系统 DSH web 占 3080，两者并存互不干扰。
;;
;; 已知未处理：异常退出（SIGKILL）可能留下 /data/ds-bot/data/bot/state.lock，
;; 届时新实例能否自行跨过尚未验证。真出现起不来的循环再补清理步骤。
;;
;; 日志写 ~/.local/state/dsh/ds-bot.log；DSH 自己另有一份
;; /data/ds-bot/data/logs/，两者不冲突。

(use-modules (shepherd service))

(register-services
 (list (service '(ds-bot)
                ;; start 必须包一层 lambda：直接给 make-forkexec-constructor
                ;; 的求值结果会把环境固化在加载时刻（见 config.org 服务构造函数段）。
                #:start (lambda args
                          ((make-forkexec-constructor
                            (list "/bin/sh" "-c"
                                  "i=0; while [ ! -f /etc/resolv.conf ] && [ $i -lt 60 ]; do i=$((i+1)); sleep 1; done; exec /run/current-system/profile/bin/podman exec my-distrobox /bin/sh -lc 'command -v fuser >/dev/null 2>&1 && fuser -k 3081/tcp 2>/dev/null; sleep 1; unset SSL_CERT_FILE; for f in /etc/ssl/certs/ca-certificates.crt /etc/pki/tls/certs/ca-bundle.crt /etc/ssl/cert.pem; do if [ -f \"$f\" ]; then export SSL_CERT_FILE=\"$f\"; break; fi; done; export DSH_HOME=/data/ds-bot/data; export DS_BOT_PORT=3081; export DS_BOT_APP=1; export DS_BOT_RUNTIME_DIR=/data/Programs/ds-bot/squashfs-root/resources; export DS_BOT_USER_DSH_HOME=/data/ds-bot/user-dsh-home; export DS_BOT_WORKSPACE=/data/ds-bot/workspace; cd /data/Programs/ds-bot/squashfs-root/resources/app; exec /data/Programs/ds-bot/squashfs-root/resources/primary-runtime/dependencies/node/bin/node src/host.mjs'")
                            #:log-file
                            "/home/brokenshine/.local/state/dsh/ds-bot.log")
                           args))
                #:stop (make-kill-destructor)
                #:respawn? #t)))

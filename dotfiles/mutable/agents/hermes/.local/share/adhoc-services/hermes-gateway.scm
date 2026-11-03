;; hermes-gateway：宿主 shepherd 拉起，经 distrobox 进 my-distrobox 跑 gateway。
;; adhoc-services 按文件名加载，服务名须与文件名一致。
;;
;; 启动命令分三层，都是围绕容器与宿主的环境错位。
;;
;; 1. 外层 sh -c 等宿主 /etc/resolv.conf 就位。该文件由 tailscale 动态重建，
;;    开机先删后写，中间有一段空窗。crun 拉起容器要 stat 这个文件，撞上窗口
;;    就报 cannot stat /etc/resolv.conf，连续失败后 shepherd 会把服务标记为
;;    禁用，之后不再自己起来。最多等 60 秒，等不到也照常往下走。
;; 2. 内层进容器后 unset SSL_CERT_FILE，再按容器发行版的证书路径重新指定，
;;    三条候选取第一条存在的。shepherd 继承宿主的登录环境，该变量指到
;;    ~/.guix-home/profile 下的 /gnu/store 证书路径，容器里没有对应的 store
;;    对象，hermes 的 httpx 建 TLS 上下文时抛 FileNotFoundError，QQ 侧每
;;    5 分钟重试一次、全部失败。
;; 3. exec 之前清掉容器内的 ~/.hermes/gateway.pid 与 gateway.lock。旧 pid
;;    文件指向已死进程时，新 gateway 读到就判定已有实例在服务，打印
;;    already serves profile 后以退出码 0 结束，shepherd 照样重启，形成
;;    每 6 秒一轮的死循环。gateway stop 清不掉这个文件，必须直接删。
;;
;; 不加 --replace：新实例踢前任会让前任退出码非 0，respawn 再起，形成自踢循环。
;; 容器内路径写死为容器视角的绝对路径（/home/brokenshine 是容器 home）。

(use-modules (shepherd service))

(register-services
 (list (service '(hermes-gateway)
                ;; start 必须包一层 lambda：直接给 make-forkexec-constructor
                ;; 的求值结果会把环境固化在加载时刻（见 config.org 服务构造函数段）。
                #:start (lambda args
                          ((make-forkexec-constructor
                            (list "/bin/sh" "-c"
                                  "i=0; while [ ! -f /etc/resolv.conf ] && [ $i -lt 60 ]; do i=$((i+1)); sleep 1; done; exec /run/current-system/profile/bin/distrobox enter --no-tty my-distrobox -- /bin/sh -lc 'unset SSL_CERT_FILE; for f in /etc/ssl/certs/ca-certificates.crt /etc/pki/tls/certs/ca-bundle.crt /etc/ssl/cert.pem; do if [ -f \"$f\" ]; then export SSL_CERT_FILE=\"$f\"; break; fi; done; /home/brokenshine/.local/bin/hermes -p default gateway stop >/dev/null 2>&1; sleep 1; rm -f /home/brokenshine/.hermes/gateway.pid /home/brokenshine/.hermes/gateway.lock; exec /home/brokenshine/.local/bin/hermes gateway run'")
                            #:log-file
                            "/home/brokenshine/.local/state/shepherd/hermes-gateway.log")
                           args))
                #:stop (make-kill-destructor)
                #:respawn? #t)))

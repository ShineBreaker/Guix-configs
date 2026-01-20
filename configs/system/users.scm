(use-modules (gnu packages shells))

(define %timezone-config
  "Asia/Shanghai")
(define %locale-config
  "zh_CN.utf8")
(define %host-name-config
  "BrokenShine-Desktop")
(define %users-config
  (cons (user-account
          (name username)
          (group "users")
          (password
           "$6$C2H4Td9gJHEa4qFi$fN.tnh2XibU1aqHpwcq.zewxyMeHR83EyP0r8UROzjj6l88VijpOogCbVarmrlCnig8k967wT7ifcJAZunZ.l.")
          (supplementary-groups '("cgroup" "wheel" "netdev" "audio" "video"))
          (shell (file-append fish "/bin/fish"))) %base-user-accounts))

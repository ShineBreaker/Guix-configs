set shell := ["fish", "-c"]

channel-fresh := "./configs/channel.scm"
channel := "./configs/channel.lock"
syscfg := "./configs/system-config.scm"
homecfg := "./configs/home-config.scm"

guix := "guix time-machine -C " + channel + " -- "

# 应用全局配置
rebuild:
	@echo 正在应用系统配置
	sudo {{guix}} system reconfigure {{syscfg}} > /dev/null

	@echo 正在应用用户配置
	{{guix}} home reconfigure {{homecfg}} > /dev/null


# 应用全局配置 (详细显示日志)
rebuild-v:
	@echo 正在应用系统配置
	sudo {{guix}} system reconfigure {{syscfg}}
	@echo 正在应用用户配置
	{{guix}} home reconfigure {{homecfg}}

# 应用系统配置
system:
  sudo {{guix}} system reconfigure {{syscfg}} > /dev/null

# 应用系统配置 (详细显示日志)
system-v:
  sudo {{guix}} system reconfigure {{syscfg}}

# 应用用户配置
home:
  {{guix}} home reconfigure {{homecfg}} > /dev/null

# 应用用户配置 (详细显示日志)
home-v:
  {{guix}} home reconfigure {{homecfg}}

# 更新lock file
upgrade:
  guix time-machine -C {{channel-fresh}} -- describe --format=channels > {{channel}}

# 格式化代码
style *args:
  guix style --whole-file {{args}}

# 格式化所有代码
style-all:
  @echo '正在对./下的文件操作中...'
  guix style --whole-file ./*.scm
  @echo '正在对./configs下的文件操作中...'
  guix style --whole-file ./configs/*.scm
  @echo '正在对./configs/home下的文件操作中...'
  guix style --whole-file ./configs/home/*.scm
  @echo '正在对./configs/home/services下的文件操作中...'
  guix style --whole-file ./configs/home/services/*.scm
  @echo '正在对./configs/system下的文件操作中...'
  guix style --whole-file ./configs/home/*.scm

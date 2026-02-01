set shell := ["fish", "-c"]

channel-fresh := "./configs/channel.scm"
channel := "./configs/channel.lock"
syscfg := "./configs/system-config.scm"
homecfg := "./configs/home-config.scm"

guix := "guix time-machine -C " + channel + " -- "

# 应用全局配置
rebuild:
	@echo \n正在应用系统配置
	sudo {{guix}} system reconfigure {{syscfg}} > /dev/null

	@echo \n正在应用用户配置
	{{guix}} home reconfigure {{homecfg}} > /dev/null


# 应用全局配置 (详细显示日志)
rebuild-v:
	@echo \n正在应用系统配置
	sudo {{guix}} system reconfigure {{syscfg}}
	@echo \n正在应用用户配置
	{{guix}} home reconfigure {{homecfg}}

# 应用系统配置
system:
  @echo \n
  sudo {{guix}} system reconfigure {{syscfg}} > /dev/null

# 应用系统配置 (详细显示日志)
system-v:
  @echo \n
  sudo {{guix}} system reconfigure {{syscfg}}

# 应用用户配置
home:
  @echo \n
  {{guix}} home reconfigure {{homecfg}} > /dev/null

# 应用用户配置 (详细显示日志)
home-v:
  @echo \n
  {{guix}} home reconfigure {{homecfg}}

# 更新lock file
upgrade:
  @echo \n
  guix time-machine -C {{channel-fresh}} -- describe --format=channels > {{channel}}

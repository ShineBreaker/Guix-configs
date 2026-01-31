set shell := ["fish", "-c"]

channel-fresh := "./configs/channel.scm"
channel := "./configs/channel.lock"
syscfg := "./configs/system-config.scm"
homecfg := "./configs/home-config.scm"

guix := "guix time-machine -C " + channel + " -- "

# 应用全局配置
rebuild:
	@echo \n正在应用系统配置
	sudo {{guix}} system reconfigure {{syscfg}} --allow-downgrades
	@echo \n正在应用用户配置
	{{guix}} home reconfigure {{homecfg}} --allow-downgrades

# 应用系统配置
system:
  @echo \n
  sudo {{guix}} system reconfigure {{syscfg}} --allow-downgrades

# 应用用户配置
home:
  @echo \n
  {{guix}} home reconfigure {{homecfg}} --allow-downgrades

# 更新lock file
upgrade:
  @echo \n
  guix time-machine -C {{channel-fresh}} -- describe --format=channels > {{channel}}

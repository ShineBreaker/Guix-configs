set shell := ["fish", "-c"]

channel-fresh := "./configs/channel.scm"
channel := "./configs/channel.lock"
syscfg := "./system-config.scm"
homecfg := "./home-config.scm"

guix := "guix time-machine -C " + channel + " -- "

# 应用全局配置
rebuild:
	echo "正在应用系统配置"
	sudo {{guix}} system reconfigure {{syscfg}} --allow-downgrades
	echo "正在应用用户配置"
	{{guix}} home reconfigure {{homecfg}} --allow-downgrades

# 应用系统配置
system:
	sudo {{guix}} system reconfigure {{syscfg}} --allow-downgrades

# 应用用户配置
user:
	{{guix}} home reconfigure {{homecfg}} --allow-downgrades

# 更新lock file.
upgrade:
  guix time-machine -C {{channel-fresh}} -- describe --format=channels > {{channel}}

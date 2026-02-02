set shell := ["bash", "-c"]

channel-fresh := "./configs/channel.scm"
channel := "./configs/channel.lock"
homecfg := "./tmp/home-config.scm"
initcfg := "./tmp/init-config.scm"
syscfg := "./tmp/system-config.scm"

configen := "./configen.sh"

guix := "guix time-machine -C " + channel + " -- "

# 生成用于安装系统的配置文件
generate-init-config:
  {{configen}} init
  guix style --whole-file {{initcfg}}

# 只生成系统配置
generate-system-config:
  {{configen}} system
  guix style --whole-file {{syscfg}}

# 只生成 home 配置
generate-home-config:
  {{configen}} home
  guix style --whole-file {{homecfg}}

# 清理临时文件
tmprm:
  @rm -rf ./tmp

# 安装系统
init: generate-init-config
  @echo 正在安装系统
  sudo {{guix}} system init {{initcfg}} /mnt
  @rm -rf ./tmp

# 应用全局配置
rebuild: generate-system-config generate-home-config
	@echo 正在应用系统配置
	sudo {{guix}} system reconfigure {{syscfg}} > /dev/null

	@echo 正在应用用户配置
	{{guix}} home reconfigure {{homecfg}} > /dev/null

	@echo 清理临时文件
	@rm -rf ./tmp


# 应用全局配置 (详细显示日志)
rebuild-v: generate-system-config generate-home-config
	@echo 正在应用系统配置
	sudo {{guix}} system reconfigure {{syscfg}}
	@echo 正在应用用户配置
	{{guix}} home reconfigure {{homecfg}}
	@echo 清理临时文件
	@rm -rf ./tmp

# 应用系统配置
system: generate-system-config
  sudo {{guix}} system reconfigure {{syscfg}} > /dev/null
  @rm -rf ./tmp

# 应用系统配置 (详细显示日志)
system-v: generate-system-config
  sudo {{guix}} system reconfigure {{syscfg}}
  @rm -rf ./tmp

# 应用用户配置
home: generate-home-config
  {{guix}} home reconfigure {{homecfg}} > /dev/null
  @rm -rf ./tmp

# 应用用户配置 (详细显示日志)
home-v: generate-home-config
  {{guix}} home reconfigure {{homecfg}}
  @rm -rf ./tmp

# 更新lock file
upgrade:
  guix time-machine -C {{channel-fresh}} -- describe --format=channels > {{channel}}

# 拉取channel
pull:
  {{guix}} pull

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

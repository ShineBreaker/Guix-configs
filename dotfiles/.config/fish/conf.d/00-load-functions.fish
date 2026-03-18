# 确定 functions 目录路径
set -l functions_dir

if set -q XDG_CONFIG_HOME
    set functions_dir $XDG_CONFIG_HOME/fish/functions
else
    set functions_dir $HOME/.config/fish/functions
end

# 如果 functions 目录存在，加载其中的所有 .fish 文件
if test -d $functions_dir
    # 按字母顺序加载所有 .fish 文件
    for func_file in $functions_dir/*.fish
        if test -f $func_file
            source $func_file
        end
    end
end

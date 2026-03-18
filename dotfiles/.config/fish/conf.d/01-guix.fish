status --is-login; and not set -q __fish_login_config_sourced
and begin

  fenv source $HOME/.profile
  set -e fish_function_path[1]

  set -g __fish_login_config_sourced 1

end

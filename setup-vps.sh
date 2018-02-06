#!/usr/bin/env bash
# Script to set up a basic Debian VPS

# Check condtions to run script
precheck() {
  if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root" 
    exit 1
  fi

  if [[ ${BASH_VERSION:0:1} -lt 4 ]];then
    echo "This script requires at least Bash version 4 to run" 
    exit 1
  fi
}

# Confirm yes/no
# Default to yes unless N is passed as second argument
# ex. confirm "Are you sure?" && response=1
confirm() {
  local prompt default reply

  while true; do

    if [ "${2:-}" = "N" ]; then
      prompt="y/N"
      default=N
    else
      prompt="Y/n"
      default=Y
    fi

    read -e -p "$1 [${prompt}] " reply

    # Default?
    if [ -z "$reply" ]; then
      reply=$default
    fi

    # Check if the reply is valid
    case "$reply" in
      Y*|y*) return 0 ;;
      N*|n*) return 1 ;;
    esac

  done
}

# Return 0 if first argument is empty, 1 otherwise
check() {
  if [ -z "$1" ];then 
    return 1
  else
    return 0
  fi
}


# Configures from user settings
# Variables
# $user - Username of new user to create
# $pass - Password for new user

# Boolean flags - any length >0 is true
# $copy_root_ssh - Copy ssh authorized keys from root
configure() {
  # Random default password
  pass=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 10)

  echo "Configuration options. Press Enter to use defaults"
  read -e -p "Username of new user: " -i "user" user
  read -e -p "Password of new user: " -i "$pass" pass

  confirm "Copy ssh key from root?" && copy_root_ssh=1

  echo "Configuration complete. The script will now run automatically"
}

# Installs base apt packages
install_base_packages() {
  apt-get -y update
  apt-get -y upgrade
  apt-get -y install sudo git ufw build-essential
}

install_additional_packages() {
  apt-get -y install vim tmux bash-completion tree 
}


# Sets up ufw firewall
setup_firewall() {
  ufw allow ssh
  ufw enable --force
}

# Create a new user with a login shell
create_login_user() {
  adduser --disabled-password --gecos "" "${user}"
  echo "${user}:${pass}" | chpasswd
  mkdir -p "/home/${user}/.ssh"

  # Copy root ssh authorized keys
  check $copy_root_ssh && cp "${HOME}/.ssh/authorized_keys" "/home/${user}/.ssh/"

  touch "/home/${user}/.ssh/authorized_keys"

  # Other helpful directories for user
  mkdir -p "/home/${user}/tmp"
  mkdir -p "/home/${user}/bin"

  chmod 700 "/home/${user}/.ssh"
  chmod 600 "/home/${user}/.ssh/authorized_keys"

  chown -R "${user}:${user}"  "/home/${user}"
}

#BEGIN

precheck
configure
install_base_packages
install_additional_packages
setup_firewall
create_login_user

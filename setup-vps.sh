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

# Read a number, ensuring it is in a range 
# Usage: checkint N MIN [MAX]
checkint() {
  n=$1
  min=$2
  max=$3

  if [[ -n "$max" ]]; then
    (( n>=min && n<=max )) && return 0
  else
    (( n>=min )) && return 0
  fi
  return 1 # Did not pass tests
}

# Exit with a fatal error
fatal() {
  echo "$@" >&2
  exit 1
}


# Configures from user settings
# Variables
# $user - Username of new user to create
# $pass - Password for new user
# $ssh_port - Port to run ssh server on

# Boolean flags - any length >0 is true
# $copy_root_ssh - Copy ssh authorized keys from root
configure() {
  # Random default password
  pass=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 10)

  echo "Configuration options. Press Enter to use defaults"
  read -e -p "Username of new user: " -i "user" user
  read -e -p "Password of new user: " -i "$pass" pass
  read -e -p "SSH Server Port: " -i "2022" ssh_port

  confirm "Copy ssh key from root?" && copy_root_ssh=1

  check_config

  echo "Configuration complete. The script will now run automatically"
}

# Validate user input variables
check_config() {
  checkint $ssh_port 1 65535 || fatal "Invalid ssh port: ${ssh_port}"
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


# Configure ssh, such as changing default port
configure_ssh() {
  # Change SSH port
  sed -i 's/^#?Port .*/Port '"${ssh_port}/" /etc/ssh/sshd_config
}

# Sets up ufw firewall
setup_firewall() {
  ufw allow "$ssh_port"
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
configure_ssh
setup_firewall
create_login_user


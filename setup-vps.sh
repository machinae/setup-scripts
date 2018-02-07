#!/usr/bin/env bash
# Script to set up a basic Debian VPS

# Globals
# Colots
RED='\033[0;31m'
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color
# End Globals

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
  printf "${RED}ERROR:${NC} ${@}\n" >&2
  exit 1
}

# Print a warning
warn() {
  printf "${YELLOW}WARNING:${NC} ${@}\n" >&2
}


# Configures from user settings
# Variables
# $user - Username of new user to create
# $pass - Password for new user
# $ssh_port - Port to run ssh server on

# Boolean flags - any length >0 is true
# $copy_root_ssh - Copy ssh authorized keys from root
# $nopasswd - Passwordless(ssh key only) login and sudo
configure() {
  # Random default password
  #pass=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 10)

  echo "Configuration options. Press Enter to use defaults"
  read -e -p "Username of new user: " -i "user" user
  read -e -p "Password of new user(leave blank for passwordless): " pass
  read -e -p "SSH Server Port: " -i "2022" ssh_port

  confirm "Copy ssh key from root?" && copy_root_ssh=1

  check_config

  echo "Configuration complete. The script will now run automatically"
}

# Validate user input variables
check_config() {
  checkint $ssh_port 1 65535 || fatal "Invalid ssh port: ${ssh_port}"
  if [[ -z "$pass" ]];then
    nopasswd=1
  fi
}

# Installs base apt packages
install_base_packages() {
  apt-get -y update
  apt-get -y upgrade
  apt-get -y install sudo git ufw ntp ca-certificates build-essential
}

install_additional_packages() {
  apt-get -y install vim tmux bash-completion tree wget curl
}


# Configure ssh, such as changing default port
configure_ssh() {
  # Change SSH port
  sed -E -i "s/^#?Port .*/Port ${ssh_port}/" /etc/ssh/sshd_config
  # Set secure SSH Defaults
  sed -E -i 's/^#?X11Forwarding .*/X11Forwarding no/' /etc/ssh/sshd_config

  # If user has SSH keys, disable password auth
  # DANGEROUS!!
  if [[ -n "$nopasswd" ]];then
    sed -E -i 's/^#?PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config
  fi


  systemctl restart ssh
}

# Configure sudoers to default user
configure_sudo() {
  local f
  f="/etc/sudoers.d/10-defaults"
  # Disable sudo lecture
  echo 'Defaults lecture="never"' >> "$f"
  # 1 hour password timeout after sudo
  echo 'Defaults timestamp_timeout=60' >> "$f"
  chmod 440 "$f"

  #Passwordless sudo for user
  if [[ -n "$nopasswd" ]];then
    f="/etc/sudoers.d/90-default-user"
    echo "${user} ALL=(ALL) NOPASSWD:ALL" >>"$f"
    chmod 440 "$f"
  fi
}

# Sets up ufw firewall
setup_firewall() {
  ufw allow "$ssh_port"
  ufw enable --force
}

# Set up swap file equal to RAM
setup_swap() {
  local swapfile swapsize diskspace
  swapfile="/swapfile"
  # Swap size in bytes
  swapsize=$(swapon --bytes --noheadings --show=SIZE|head -n1)
  # Available disk space in bytes
  diskspace=$(df --output=avail /|tail -n1)
  # Return if swap already exits
  if [[ "$swapsize" > 0 ]];then
    return
  fi

  # Set swap size to available memory
  swapsize=$(free -b |awk '/Mem/ {print $2}')

  # Sanity check for swap size
  if [[ "$swapsize" > "$diskspace" ]];then
    fatal "Swap file size too big: ${swapsize} bytes"
  fi

  fallocate -l "$swapsize" "$swapfile"
  chmod 600 "$swapfile"

  mkswap "$swapfile"
  swapon "$swapfile"
  echo "${swapfile} none swap sw 0 0" >>/etc/fstab

  # Lower swappiness to use swap less frequently
  sysctl vm.swappiness=40
  echo "vm.swappiness=40" >>/etc/sysctl.conf
  sysctl vm.vfs_cache_pressure=50
  echo "vm.vfs_cache_pressure=50" >>/etc/sysctl.conf
}

# Create a new user with a login shell
create_login_user() {
  adduser --disabled-password --gecos "" "${user}"
  usermod -aG adm,sudo "${user}"

  if [[ -n "$pass" ]];then
    echo "${user}:${pass}" | chpasswd
  fi

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

# Show config status
checkstatus() {
  if [[ -n "$nopasswd" && ! -s "/home/${user}/.ssh/authorized_keys" ]]; then
    warn "Passwordless mode enabled, but ${user} has no ssh keys!" 
    echo "Make sure to add at least one key to /home/${user}/authorized_keys"
  fi
  echo -e "${GREEN}Setup completed!${NC}"
}

#BEGIN

precheck
configure

install_base_packages
install_additional_packages
setup_swap

configure_ssh
setup_firewall
create_login_user
configure_sudo

checkstatus

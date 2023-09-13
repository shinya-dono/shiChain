#!/usr/bin/env bash

#  shichain is a commandline helper for installing xray and configuring a safe tunnel
#  through local relays to the internet. It is designed to be used on a remote
#  server to provide a secure connection to the internet for a local client.
#  It is not designed to be used on a local client.
#
# CAUTION: This script is designed to be run on a ubuntu server.
# any other OS is not supported.
#
#  3 modes are supported:
#  1. install xray and configure a relay
#    - this option will install xray and configure a relay on the local server, typically in iran.
#  2. install xray and configure an outbound tunnel
#    - this option will install xray and configure an outbound tunnel on the foreign server, typically in your DE server or sth.
#    - you can purchase a foreign server from https://ishosting.com/ , https://pq.hosting/ , https://aeza.net/ or any provider you like.
#  3. install namizun
#    - this option will install namizun on the local server, typically in iran.
#    - namizun is used to create dummy outbound traffic to confuse the DPI and authorities.

set -e

# text formatting options
bold=$(tput bold)
normal=$(tput sgr0)
italic=$(tput sitm)

# text colors
error=$(tput setaf 1)
info=$(tput setaf 2)
warning=$(tput setaf 3)
secondary=$(tput setaf 4)
shinya=$(tput setaf 5)

# declare variables

INSTALL_PATH=${INSTALL_PATH:-/etc/shichain}
XRAY_PATH=${XRAY_PATH:-$INSTALL_PATH/xray}
CONFIG_PATH=${CONFIG_PATH:-$INSTALL_PATH/config.json}
IRAN_DAT_FILE=${IRAN_DAT_FILE:-$INSTALL_PATH/iran.dat}
LOG_PATH=${LOG_PATH:-/var/log/shichain}
INSTALL_USER=${INSTALL_USER:-nobody}

$IP=$(curl -s icanhazip.com)

# Two very important variables
TMP_DIRECTORY="$(mktemp -d)"
ZIP_FILE="${TMP_DIRECTORY}/Xray.zip"

# Xray version will be installed
INSTALL_VERSION='v1.8.4'

# --proxy ?
PROXY=${PROXY:-''}

detect_os() {
  if [[ "$(uname)" == 'Linux' ]]; then
    case "$(uname -m)" in
    'i386' | 'i686')
      MACHINE='32'
      ;;
    'amd64' | 'x86_64')
      MACHINE='64'
      ;;
    'armv5tel')
      MACHINE='arm32-v5'
      ;;
    'armv6l')
      MACHINE='arm32-v6'
      grep Features /proc/cpuinfo | grep -qw 'vfp' || MACHINE='arm32-v5'
      ;;
    'armv7' | 'armv7l')
      MACHINE='arm32-v7a'
      grep Features /proc/cpuinfo | grep -qw 'vfp' || MACHINE='arm32-v5'
      ;;
    'armv8' | 'aarch64')
      MACHINE='arm64-v8a'
      ;;
    'mips')
      MACHINE='mips32'
      ;;
    'mipsle')
      MACHINE='mips32le'
      ;;
    'mips64')
      MACHINE='mips64'
      lscpu | grep -q "Little Endian" && MACHINE='mips64le'
      ;;
    'mips64le')
      MACHINE='mips64le'
      ;;
    'ppc64')
      MACHINE='ppc64'
      ;;
    'ppc64le')
      MACHINE='ppc64le'
      ;;
    'riscv64')
      MACHINE='riscv64'
      ;;
    's390x')
      MACHINE='s390x'
      ;;
    *)
      echo -e " ${error} The architecture is not supported. ${normal}"
      exit 1
      ;;
    esac
    if [[ ! -f '/etc/os-release' ]]; then
      echo -e " ${error} Don't use outdated Linux distributions. ${normal}"
      exit 1
    fi

    if [[ -f /.dockerenv ]] || grep -q 'docker\|lxc' /proc/1/cgroup && [[ "$(type -P systemctl)" ]]; then
      true
    elif [[ -d /run/systemd/system ]] || grep -q systemd <(ls -l /sbin/init); then
      true
    else
      echo -e " ${error} Only Linux distributions using systemd are supported. ${normal}"
      exit 1
    fi
    if [[ "$(type -P apt)" ]]; then
      PACKAGE_MANAGEMENT_INSTALL='apt -y --no-install-recommends install'
      PACKAGE_MANAGEMENT_REMOVE='apt purge'
      package_provide_tput='ncurses-bin'
    elif [[ "$(type -P dnf)" ]]; then
      PACKAGE_MANAGEMENT_INSTALL='dnf -y install'
      PACKAGE_MANAGEMENT_REMOVE='dnf remove'
      package_provide_tput='ncurses'
    elif [[ "$(type -P yum)" ]]; then
      PACKAGE_MANAGEMENT_INSTALL='yum -y install'
      PACKAGE_MANAGEMENT_REMOVE='yum remove'
      package_provide_tput='ncurses'
    elif [[ "$(type -P zypper)" ]]; then
      PACKAGE_MANAGEMENT_INSTALL='zypper install -y --no-recommends'
      PACKAGE_MANAGEMENT_REMOVE='zypper remove'
      package_provide_tput='ncurses-utils'
    elif [[ "$(type -P pacman)" ]]; then
      PACKAGE_MANAGEMENT_INSTALL='pacman -Syu --noconfirm'
      PACKAGE_MANAGEMENT_REMOVE='pacman -Rsn'
      package_provide_tput='ncurses'
    elif [[ "$(type -P emerge)" ]]; then
      PACKAGE_MANAGEMENT_INSTALL='emerge -qv'
      PACKAGE_MANAGEMENT_REMOVE='emerge -Cv'
      package_provide_tput='ncurses'
    else
      echo -e " ${error} The script does not support the package manager in this operating system. ${normal}"
      exit 1
    fi
  else
    echo -e " ${error} This operating system is not supported. ${normal}"
    exit 1
  fi
}

detect_user() {
  if ! id $INSTALL_USER >/dev/null 2>&1; then
    echo "the user '$INSTALL_USER' is not effective"
    exit 1
  fi
  INSTALL_USER_UID="$(id -u $INSTALL_USER)"
  INSTALL_USER_GID="$(id -g $INSTALL_USER)"
}

install_software() {
  package_name="$1"
  file_to_detect="$2"
  type -P "$file_to_detect" >/dev/null 2>&1 && return
  if ${PACKAGE_MANAGEMENT_INSTALL} "$package_name" >/dev/null 2>&1; then
    echo -e "${info}\t $package_name is installed. ${normal}"
  else
    echo -e "${error}\t $package_name could not be installed. ${normal}"
    exit 1
  fi
}

install_xray() {
  DOWNLOAD_LINK="https://github.com/XTLS/Xray-core/releases/download/$INSTALL_VERSION/Xray-linux-$MACHINE.zip"

  echo -e "${info} Downloading Xray archive: $DOWNLOAD_LINK"

  if ! curl -x "${PROXY}" -R -H 'Cache-Control: no-cache' -o "$ZIP_FILE" "$DOWNLOAD_LINK"; then
    echo -e "${error} Download failed! Please check your network or try again. ${normal}"
    return 1
  fi

  return 0

  echo "Downloading verification file for Xray archive: $DOWNLOAD_LINK.dgst"

  if ! curl -x "${PROXY}" -sSR -H 'Cache-Control: no-cache' -o "$ZIP_FILE.dgst" "$DOWNLOAD_LINK.dgst"; then
    echo -e ' ${error}} Download failed! Please check your network or try again. ${normal}'
    return 1
  fi

  if [[ "$(cat "$ZIP_FILE".dgst)" == 'Not Found' ]]; then
    echo -e ' ${error}} This version does not support verification. Please replace with another version. ${normal}'
    return 1
  fi

  # Verification of Xray archive
  CHECKSUM=$(cat "$ZIP_FILE".dgst | awk -F '= ' '/256=/ {print $2}')
  LOCALSUM=$(sha256sum "$ZIP_FILE" | awk '{printf $1}')

  if [[ "$CHECKSUM" != "$LOCALSUM" ]]; then
    echo -e ' ${error} SHA256 check failed! Please check your network or try again. ${normal}'
    return 1
  fi

  if ! unzip -q "$ZIP_FILE" -d "$TMP_DIRECTORY"; then
    echo -e "${error} Xray decompression failed. ${normal}"
    "rm" -r "$TMP_DIRECTORY"
    echo "removed: $TMP_DIRECTORY"
    exit 1
  fi

  echo -e "${info} Extract the ShiChain package to $TMP_DIRECTORY and prepare it for installation. ${normal}"

  install -m 755 "${TMP_DIRECTORY}/xray" "${XRAY_PATH}"
  chown -R "$INSTALL_USER_UID:$INSTALL_USER_GID" "$LOG_PATH/"

}

install_xray_service() {
  local temp_CapabilityBoundingSet="CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE"
  local temp_AmbientCapabilities="AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE"
  local temp_NoNewPrivileges="NoNewPrivileges=true"
  if [[ "$INSTALL_USER_UID" -eq '0' ]]; then
    temp_CapabilityBoundingSet="#${temp_CapabilityBoundingSet}"
    temp_AmbientCapabilities="#${temp_AmbientCapabilities}"
    temp_NoNewPrivileges="#${temp_NoNewPrivileges}"
  fi
  cat >/etc/systemd/system/shichain.service <<EOF
[Unit]
Description=ShiChain Service
Documentation=https://github.com/shinya-dono/shichain
After=network.target nss-lookup.target

[Service]
User=$INSTALL_USER
${temp_CapabilityBoundingSet}
${temp_AmbientCapabilities}
${temp_NoNewPrivileges}
ExecStart=${XRAY_PATH} run -config ${CONFIG_PATH}
Restart=on-failure
RestartPreventExitStatus=23
LimitNPROC=10000
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF

  chmod 644 /etc/systemd/system/shichain.service

  systemctl daemon-reload
}

configure_outbound() {

  read -rp "${info} inbound port? [21432]: ${normal}" d_port
  d_port="${d_port:-21432}"

  read -rp "${info} inbound uuid? [205b09fa-31a3-499b-8450-3114e83ad092]: ${normal}" d_id
  d_id="${d_id:-205b09fa-31a3-499b-8450-3114e83ad092}"

  read -rp "${info} inbound path? [/aVerySecretPath]: ${normal}" d_path
  d_path="${d_path:-/aVerySecretPath}"

  read -rp "${info} send through ip? [0.0.0.0]: ${normal}" send_through
  send_through="${send_through:-0.0.0.0}"

  tee "$CONFIG_PATH" >/dev/null <<ENDOfMessage
{
  "log": {
    "loglevel": "warning",
    "access": "$LOG_PATH/access.log",
    "error": "$LOG_PATH/error.log"
  },
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {
        "type": "field",
        "outboundTag": "blocked",
        "protocol": [
          "bittorrent"
        ]
      },
      {
        "type": "field",
        "inboundTag": "inbound-main",
        "outboundTag": "out"
      }
    ]
  },
  "dns": null,
  "inbounds": [
    {
      "listen": null,
      "port": ${d_port},
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "alterId": 0,
            "email": "tfccjos",
            "id": "${d_id}"
          }
        ],
        "disableInsecureEncryption": false
      },
      "streamSettings": {
        "network": "tcp",
        "security": "none",
        "tcpSettings": {
          "acceptProxyProtocol": false,
          "header": {
            "type": "http",
            "request": {
              "method": "GET",
              "path": [
                "${d_path}"
              ]
            }
          }
        }
      },
      "tag": "inbound-main",
      "sniffing": {
        "enabled": false
      }
    }
  ],
  "outbounds": [
    {
      "tag": "out",
      "sendThrough": "${send_through}",
      "protocol": "freedom",
      "streamSettings": {
        "sockopt": {
          "tcpFastOpen": true
        }
      },
      "settings": {
        "domainStrategy": "AsIs"
      }
    },
    {
      "tag": "blocked",
      "protocol": "blackhole",
      "settings": {}
    }
  ]
}
ENDOfMessage

}

configure_inbound() {

  read -rp "${info} client port? [9921]: ${normal}" i_port
  i_port="${i_port:-9921}"

  default_i_id=$(uuidgen)
  read -rp "${info} server uuid? [$default_i_id]: ${normal}" i_id
  i_id="${d_id:-$default_i_id}"

  read -rp "${info} server host? ${normal}" d_host

  read -rp "${info} server port? [21432]: ${normal}" d_port
  d_port="${d_port:-21432}"

  read -rp "${info} server uuid? [205b09fa-31a3-499b-8450-3114e83ad092]: ${normal}" d_id
  d_id="${d_id:-205b09fa-31a3-499b-8450-3114e83ad092}"

  read -rp "${info} server path? [/aVerySecretPath]: ${normal}" d_path
  d_path="${d_path:-/aVerySecretPath}"

  read -rp "${info} mux? [-1]: ${reset}" mux
  mux="${mux:--1}"

  if [ "$mux" = -1 ]; then
    mux_e="false"
  else
    mux_e="true"
  fi

  tee "$CONFIG_PATH" >/dev/null <<ENDOfMessage
{
  "log": {
    "access": "$LOG_PATH/access.log",
    "error": "$LOG_PATH/error.log",
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": $i_port,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$i_id",
            "alterId": 0,
            "email": "t@t.tt",
            "flow": ""
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "tcpSettings": {
          "header": {
            "type": "http"
          }
        }
      }
    }
  ],
  "outbounds": [
    {
      "tag": "out",
      "protocol": "freedom",
      "settings": {}
    },
    {
      "tag": "proxy",
      "protocol": "vmess",
      "settings": {
        "vnext": [
          {
            "address": "$d_host",
            "port": $d_port,
            "users": [
              {
                "id": "$d_id",
                "alterId": 0,
                "email": "t@t.tt",
                "security": "auto"
              }
            ]
          }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "tcpSettings": {
          "header": {
            "type": "http",
            "request": {
              "version": "1.1",
              "method": "GET",
              "path": [
                "$d_path"
              ],
              "headers": {
                "Host": [
                  "872r7f20.divarcdn.com",
                  "872r7f20.snappfood.ir",
                  "872r7f20.yjc.ir",
                  "872r7f20.digikala.com",
                  "872r7f20.tic.ir"
                ],
                "User-Agent": [
                  "Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/55.0.2883.75 Safari/537.36",
                  "Mozilla/5.0 (iPhone; CPU iPhone OS 10_0_2 like Mac OS X) AppleWebKit/601.1 (KHTML, like Gecko) CriOS/53.0.2785.109 Mobile/14A456 Safari/601.1.46"
                ],
                "Accept-Encoding": [
                  "gzip, deflate"
                ],
                "Connection": [
                  "keep-alive"
                ],
                "Pragma": "no-cache"
              }
            }
          }
        }
      },
      "mux": {
        "enabled": $mux_e,
        "concurrency": $mux
      }
    },
    {
      "protocol": "blackhole",
      "settings": {},
      "tag": "blocked"
    }
  ],
  "routing": {
    "rules": [
      {
        "inboundTag": [
          "api"
        ],
        "outboundTag": "api",
        "type": "field"
      },
      {
        "type": "field",
        "outboundTag": "block",
        "ip": [
          "geoip:private"
        ]
      },
      {
        "type": "field",
        "outboundTag": "block",
        "protocol": [
          "bittorrent"
        ]
      },
      {
        "type": "field",
        "outboundTag": "out",
        "domain": [
          "regexp:.ir$"
        ]
      },
      {
        "type": "field",
        "outboundTag": "out",
        "domain": [
          "ext:iran.dat:ir"
        ]
      },
      {
        "type": "field",
        "outboundTag": "out",
        "domain": [
          "ext:iran.dat:other"
        ]
      },
      {
        "type": "field",
        "outboundTag": "block",
        "domain": [
          "ext:iran.dat:ads",
          "geosite:category-ads-all"
        ]
      },
      {
        "type": "field",
        "outboundTag": "proxy",
        "network": "udp,tcp"
      }
    ]
  }
}
ENDOfMessage

}

install_iran_dat() {
  if [[ ! -f "$IRAN_DAT_FILE" ]]; then
    echo -e "${info} Downloading Iran.dat ${normal}"
    if ! curl -x "${PROXY}" -R -H 'Cache-Control: no-cache' -o "$IRAN_DAT_FILE" "https://github.com/MasterKia/iran-hosted-domains/releases/latest/download/iran.dat"; then
      echo -e "${error} Download failed! Please check your network or try again. ${normal}"
      return 1
    fi
  fi
}

start_xray() {
  if [[ -f '/etc/systemd/system/shichain.service' ]]; then
    systemctl start shichain
    sleep 1s
    if systemctl -q is-active shichain; then
      echo -e "${info}\t ShiChain started. ${normal}}"
    else
      echo -e "${error}\t ShiChain failed to start.${normal}"
      exit 1
    fi
  fi
}

install_bbr() {
  wget --no-check-certificate https://github.com/teddysun/across/raw/master/bbr.sh
  chmod +x bbr.sh
  ./bbr.sh

  echo -e "${info}\t Installed successfully! ${normal}"

  main_menu
}

fix_asiatech() {
  echo "" >/etc/apt/sources.list
  echo "deb http://archive.ubuntu.asiatech.ir/ jammy main" >>/etc/apt/sources.list
  echo "deb-src http://archive.ubuntu.asiatech.ir/ jammy main" >>/etc/apt/sources.list
  sudo add-apt-repository universe -y >/dev/null
  sudo add-apt-repository multiverse -y >/dev/null
  sudo apt update >/dev/null

  echo -e "${info}All apt servers are fixed now.${normal}"

  main_menu
}

banner() {

  clear

  echo "${info}"
  echo -e " \t ███████╗██╗  ██╗██╗ ██████╗██╗  ██╗ █████╗ ██╗███╗   ██╗"
  echo -e " \t ██╔════╝██║  ██║██║██╔════╝██║  ██║██╔══██╗██║████╗  ██║"
  echo -e " \t ███████╗███████║██║██║     ███████║███████║██║██╔██╗ ██║"
  echo -e " \t ╚════██║██╔══██║██║██║     ██╔══██║██╔══██║██║██║╚██╗██║"
  echo -e " \t ███████║██║  ██║██║╚██████╗██║  ██║██║  ██║██║██║ ╚████║"
  echo -e " \t ╚══════╝╚═╝  ╚═╝╚═╝ ╚═════╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝╚═╝  ╚═══╝"
  echo "${normal}"

  echo -e "\t ${secondary}shichain is a commandline helper for installing xray and configuring a safe tunnel${normal}"
}

pre_checks() {
  if [ "$EUID" -e 0 ]; then
    echo "Please run as root"
    exit
  fi

  detect_os
  detect_user

  install_software curl curl
  install_software unzip unzip
}

main_menu() {
  banner

  echo "${info}}"
  echo -e "\t 1. install local relay [iran]"
  echo -e "\t 2. install foreign outbound tunnel [foreign server]"
  echo -e "\t 3. install namizun"
  echo
  echo -e "\t 0. exit"
  echo -e "${normal}"

  read -p "please select an option: " option

  case $option in
  1)
    install_xray_relay
    ;;
  2)
    install_xray_outbound
    ;;
  3)
    install_namizun
    ;;
  0)
    exit
    ;;
  *)
    echo -e "${error}invalid option${normal}"
    ;;
  esac
}

install_xray_relay() {
  install_xray
  configure_inbound
  install_iran_dat
  install_xray_service
  start_xray


  echo -e "${info} ShiChain installed successfully! ${normal}"

  echo -e "${info} You can now use the following configuration to connect to ShiChain: ${normal}"
  echo
  echo -e "${warning} vless://$i_id@$IP:$i_port?encryption=none&security=none&type=tcp&headerType=http&host=872r7f20.divarcdn.com%2C872r7f20.snappfood.ir%2C872r7f20.yjc.ir%2C872r7f20.digikala.com%2C872r7f20.tic.ir#ShiChan ${normal}"
  echo

  install_software qrencode qrencode

  echo -e "${info} or scan the following QR code: ${normal}"
  echo
  echo -e "${warning}"
  qrencode -t ansiutf8 <"vless://$i_id@$IP:$i_port?encryption=none&security=none&type=tcp&headerType=http&host=872r7f20.divarcdn.com%2C872r7f20.snappfood.ir%2C872r7f20.yjc.ir%2C872r7f20.digikala.com%2C872r7f20.tic.ir#ShiChan"

  read -p "press any key to continue..." -n1 -s
  main_menu

}

install_xray_outbound() {
  install_xray
  configure_outbound
  install_xray_service
  start_xray

  echo -e "${info} ShiChain installed successfully! ${normal}"

  echo -e "${info} You can now use the following configuration to connect to ShiChain: ${normal}"
  echo -e "${warning} host: $IP ${normal}"
  echo -e "${warning} port: $d_port ${normal}"
  echo -e "${warning} uuid: $d_id ${normal}"
  echo -e "${warning} path: $d_path ${normal}"

  read -p "press any key to continue..." -n1 -s
  main_menu
}

install_namizun() {

  curl https://raw.githubusercontent.com/malkemit/namizun/master/else/setup.sh | sudo bash

  read -p "press any key to continue..." -n1 -s
  main_menu
}

pre_checks
main_menu

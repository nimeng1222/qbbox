#!/bin/bash

# 默认值
WEBUI_PORT="12311"
PORT_MIN="55000"
DEFAULT_USER="waitnm"
DEFAULT_PASS="waitdxx"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
PLAIN='\033[0m'

# 进度条函数
show_progress() {
    local duration=$1
    local prefix=$2
    local width=50
    local fill="━"
    local empty="═"
    
    for ((i = 0; i <= width; i++)); do
        local progress=$((i * 100 / width))
        local completed=$((i * width / width))
        printf "\r${BLUE}${prefix} [${YELLOW}"
        printf "%${completed}s" | tr ' ' "${fill}"
        printf "%$((width - completed))s" | tr ' ' "${empty}"
        printf "${BLUE}] ${YELLOW}%3d%%${PLAIN}" $progress
        sleep $(bc <<< "scale=3; $duration/$width")
    done
    echo
}

# 获取用户输入
get_user_input() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${PLAIN}"
    echo -e "${YELLOW}欢迎使用 Wait 定制版 qBittorrent 安装脚本${PLAIN}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${PLAIN}"
    echo
    read -p "$(echo -e ${BLUE}请输入用户名 [默认: ${DEFAULT_USER}]: ${PLAIN})" USERNAME
    USERNAME=${USERNAME:-${DEFAULT_USER}}
    
    read -s -p "$(echo -e ${BLUE}请输入密码 [默认: ${DEFAULT_PASS}]: ${PLAIN})" PASSWORD
    echo
    PASSWORD=${PASSWORD:-${DEFAULT_PASS}}
    
    read -p "$(echo -e ${BLUE}请输入 WebUI 端口 [默认: ${WEBUI_PORT}]: ${PLAIN})" input_port
    WEBUI_PORT=${input_port:-${WEBUI_PORT}}
    echo
}

# 安装 qBittorrent
install_qbittorrent() {
    echo -e "${CYAN}开始安装 qBittorrent...${PLAIN}"
    show_progress 2 "安装依赖"
    apt update > /dev/null 2>&1
    apt install -y curl wget > /dev/null 2>&1
    
    cd /usr/local/bin/
    echo -e "${CYAN}下载 qBittorrent...${PLAIN}"
    show_progress 3 "下载文件"
    wget -q -O qbittorrent-nox "https://github.com/userdocs/qbittorrent-nox-static/releases/download/release-4.3.8_v1.2.14/x86_64-cmake-qbittorrent-nox"
    
    if [ $? -ne 0 ]; then
        echo -e "${YELLOW}主链接下载失败，尝试代理下载...${PLAIN}"
        wget -q -O qbittorrent-nox "https://ghproxy.com/https://github.com/userdocs/qbittorrent-nox-static/releases/download/release-4.3.8_v1.2.14/x86_64-cmake-qbittorrent-nox"
    fi
    
    chmod +x qbittorrent-nox

    show_progress 2 "创建用户"
    if ! id "${USERNAME}" >/dev/null 2>&1; then
        useradd -r -m -s /bin/false ${USERNAME}
    fi

    show_progress 2 "配置服务"
    mkdir -p /home/${USERNAME}/.config/qBittorrent
    mkdir -p /home/${USERNAME}/downloads
    
    # 配置文件
    CONFIG_FILE="/home/${USERNAME}/.config/qBittorrent/qBittorrent.conf"
    
    cat > ${CONFIG_FILE} << EOF
[LegalNotice]
Accepted=true

[Preferences]
WebUI\Port=${WEBUI_PORT}
WebUI\Username=${USERNAME}
WebUI\Password_ha1=$(echo -n "${PASSWORD}" | md5sum | cut -d ' ' -f 1)
General\Locale=zh
Advanced\DiskCache=-1
Downloads\PreAllocation=false
Connection\PortRangeMin=${PORT_MIN}
WebUI\CSRFProtection=false
Downloads\SavePath=/home/${USERNAME}/downloads
Bittorrent\MaxConnecs=-1
Bittorrent\MaxConnecsPerTorrent=-1
Bittorrent\MaxUploads=-1
Bittorrent\MaxUploadsPerTorrent=-1
Bittorrent\uTP_rate_limited=false
Connection\SocketBacklogSize=1024
Downloads\DiskWriteCacheSize=-1
Downloads\SaveResumeDataInterval=1
Advanced\AsyncIO=true
Downloads\MaxActiveDownloads=-1
Downloads\MaxActiveUploads=-1
Downloads\MaxActiveTorrents=-1
EOF

    # 创建服务
    cat > /etc/systemd/system/qbittorrent-nox@.service << EOF
[Unit]
Description=qBittorrent-nox service for %i
After=network.target

[Service]
Type=simple
User=%i
ExecStart=/usr/local/bin/qbittorrent-nox --webui-port=${WEBUI_PORT}
Restart=always
LimitNOFILE=1048576
LimitNPROC=infinity
TasksMax=infinity
Nice=-10
IOSchedulingClass=best-effort
IOSchedulingPriority=0

[Install]
WantedBy=multi-user.target
EOF

    chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}
    
    systemctl daemon-reload
    systemctl enable qbittorrent-nox@${USERNAME}
    systemctl start qbittorrent-nox@${USERNAME}
}

# 系统优化
optimize_system() {
    echo -e "${CYAN}优化系统设置...${PLAIN}"
    show_progress 3 "系统优化"
    
    cat > /etc/security/limits.conf << EOF
* soft nofile 1048576
* hard nofile 1048576
${USERNAME} soft nofile 1048576
${USERNAME} hard nofile 1048576
* soft nproc unlimited
* hard nproc unlimited
EOF

    cat > /etc/sysctl.conf << EOF
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.core.rmem_default = 65536
net.core.wmem_default = 65536
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864
net.core.netdev_max_backlog = 32768
net.core.somaxconn = 32768
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_congestion_control = bbr
net.core.default_qdisc = fq
fs.file-max = 6815744
EOF

    sysctl -p > /dev/null 2>&1
}

# 主函数
main() {
    if [ "$EUID" -ne 0 ]; then 
        echo -e "${RED}请使用 root 权限运行此脚本${PLAIN}"
        exit 1
    fi

    clear
    echo -e "${PURPLE}
    ██╗    ██╗ █████╗ ██╗████████╗    ██████╗ ██████╗ ██╗████████╗
    ██║    ██║██╔══██╗██║╚══██╔══╝    ██╔══██╗██╔══██╗██║╚══██╔══╝
    ██║ █╗ ██║███████║██║   ██║       ██████╔╝██████╔╝██║   ██║   
    ██║███╗██║██╔══██║██║   ██║       ██╔══██╗██╔══██╗██║   ██║   
    ╚███╔███╔╝██║  ██║██║   ██║       ██████╔╝██████╔╝██║   ██║   
     ╚══╝╚══╝ ╚═╝  ╚═╝╚═╝   ╚═╝       ╚═════╝ ╚═════╝ ╚═╝   ╚═╝   
                                                     By Wait Team
    ${PLAIN}"
    
    get_user_input
    install_qbittorrent
    optimize_system

    # 获取公网 IP
    IP=$(curl -s ip.sb)
    
    clear
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${PLAIN}"
    echo -e "${GREEN} Wait 定制版 qBittorrent 安装成功！${PLAIN}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${PLAIN}"
    echo -e ""
    echo -e "${YELLOW} WebUI 信息：${PLAIN}"
    echo -e "${GREEN} 访问地址：${PLAIN}${BLUE}http://${IP}:${WEBUI_PORT}${PLAIN}"
    echo -e "${GREEN} 用户名：${PLAIN}${BLUE}${USERNAME}${PLAIN}"
    echo -e "${GREEN} 密码：${PLAIN}${BLUE}${PASSWORD}${PLAIN}"
    echo -e "${GREEN} 下载目录：${PLAIN}${BLUE}/home/${USERNAME}/downloads${PLAIN}"
    echo -e ""
    echo -e "${YELLOW} 定制优化：${PLAIN}"
    echo -e "${GREEN} - 自动配置最佳性能参数${PLAIN}"
    echo -e "${GREEN} - 优化系统网络设置${PLAIN}"
    echo -e "${GREEN} - Wait 专属优化配置${PLAIN}"
    echo -e ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${PLAIN}"
    echo -e "${YELLOW} 系统将在 20 秒后重启...${PLAIN}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${PLAIN}"
    
    sleep 20
    reboot
}

main
exit 0

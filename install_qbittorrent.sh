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
    local width=20
    local fill="━"
    local empty="═"
    
    echo -ne "${BLUE}${prefix} [${YELLOW}"
    for ((i = 0; i <= width; i++)); do
        echo -n "${fill}"
        sleep 0.1
    done
    echo -ne "${BLUE}] ${YELLOW}100%${PLAIN}\n"
}

# 检查是否已安装
check_installed() {
    if [ -f "/usr/local/bin/qbittorrent-nox" ]; then
        echo -e "${YELLOW}检测到已安装 qBittorrent${PLAIN}"
        read -p "$(echo -e ${BLUE}是否卸载旧版本？[y/n]:${PLAIN})" choice
        if [[ $choice == "y" || $choice == "Y" ]]; then
            uninstall_qbittorrent
        else
            echo -e "${RED}安装已取消${PLAIN}"
            exit 1
        fi
    fi
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
    if ! id "${DEFAULT_USER}" >/dev/null 2>&1; then
        useradd -m -s /bin/bash ${DEFAULT_USER}
    fi

    show_progress 2 "配置服务"
    
    # 先停止可能运行的实例
    systemctl stop qbittorrent-nox@${DEFAULT_USER} 2>/dev/null
    
    # 删除可能存在的旧配置和目录
    rm -rf /home/${DEFAULT_USER}/.config/qBittorrent
    rm -rf /home/${DEFAULT_USER}/.local/share/qBittorrent
    rm -rf /home/${DEFAULT_USER}/downloads

    # 创建所有必需的目录
    mkdir -p /home/${DEFAULT_USER}/.config/qBittorrent/cache
    mkdir -p /home/${DEFAULT_USER}/.config/qBittorrent/logs
    mkdir -p /home/${DEFAULT_USER}/.local/share/qBittorrent
    mkdir -p /home/${DEFAULT_USER}/downloads
    mkdir -p /home/${DEFAULT_USER}/downloads/temp

    # 设置正确的权限
    chown -R ${DEFAULT_USER}:${DEFAULT_USER} /home/${DEFAULT_USER}
    chmod -R 755 /home/${DEFAULT_USER}
    
    # 创建服务文件
    cat > /etc/systemd/system/qbittorrent-nox@.service << EOF
[Unit]
Description=qBittorrent-nox service for %i
After=network.target

[Service]
Type=simple
User=%i
WorkingDirectory=/home/%i
Environment="XDG_CONFIG_HOME=/home/%i/.config"
ExecStart=/usr/local/bin/qbittorrent-nox
Restart=on-failure
TimeoutStopSec=20
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    # 创建默认配置文件
    CONFIG_FILE="/home/${DEFAULT_USER}/.config/qBittorrent/qBittorrent.conf"
    cat > ${CONFIG_FILE} << EOF
[LegalNotice]
Accepted=true

[Preferences]
WebUI\Port=${WEBUI_PORT}
WebUI\Username=${DEFAULT_USER}
WebUI\Password_ha1=$(echo -n "${DEFAULT_USER}:qBittorrent:${DEFAULT_PASS}" | md5sum | cut -d ' ' -f 1)
Downloads\SavePath=/home/${DEFAULT_USER}/downloads
Downloads\TempPath=/home/${DEFAULT_USER}/downloads/temp
Connection\PortRangeMin=${PORT_MIN}
General\Locale=zh
WebUI\CSRFProtection=false
WebUI\ClickjackingProtection=false
EOF

    # 设置配置文件权限
    chown ${DEFAULT_USER}:${DEFAULT_USER} ${CONFIG_FILE}
    chmod 644 ${CONFIG_FILE}

    # 重新加载systemd并启动服务
    systemctl daemon-reload
    systemctl enable qbittorrent-nox@${DEFAULT_USER}
    systemctl start qbittorrent-nox@${DEFAULT_USER}
    
    # 等待服务启动
    echo -e "${YELLOW}等待服务启动...${PLAIN}"
    sleep 5
    
    # 获取服务状态
    if systemctl is-active --quiet qbittorrent-nox@${DEFAULT_USER}; then
        echo -e "${GREEN}qBittorrent 安装成功！${PLAIN}"
        IP=$(curl -s ip.sb)
        echo -e "${YELLOW}WebUI 访问信息：${PLAIN}"
        echo -e "地址：${GREEN}http://${IP}:${WEBUI_PORT}${PLAIN}"
        echo -e "用户名：${GREEN}${DEFAULT_USER}${PLAIN}"
        echo -e "密码：${GREEN}${DEFAULT_PASS}${PLAIN}"
    else
        echo -e "${RED}服务启动失败，请检查日志：${PLAIN}"
        journalctl -u qbittorrent-nox@${DEFAULT_USER} -n 50 --no-pager
    fi
}

# 卸载函数
uninstall_qbittorrent() {
    clear
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${PLAIN}"
    echo -e "${YELLOW} 开始卸载 Wait 定制版 qBittorrent...${PLAIN}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${PLAIN}"
    
    show_progress 2 "停止服务"
    systemctl stop qbittorrent-nox@${DEFAULT_USER} 2>/dev/null
    systemctl disable qbittorrent-nox@${DEFAULT_USER} 2>/dev/null
    
    show_progress 2 "删除文件"
    rm -f /usr/local/bin/qbittorrent-nox
    rm -f /etc/systemd/system/qbittorrent-nox@.service
    
    show_progress 2 "清理配置"
    read -p "$(echo -e ${BLUE}是否删除配置文件和下载目录？(y/n): ${PLAIN})" choice
    if [[ $choice == "y" || $choice == "Y" ]]; then
        rm -rf /home/${DEFAULT_USER}/.config/qBittorrent
        rm -rf /home/${DEFAULT_USER}/.local/share/qBittorrent
        rm -rf /home/${DEFAULT_USER}/downloads
    fi
    
    show_progress 2 "删除用户"
    read -p "$(echo -e ${BLUE}是否删除用户 ${DEFAULT_USER}？(y/n): ${PLAIN})" choice
    if [[ $choice == "y" || $choice == "Y" ]]; then
        userdel -r ${DEFAULT_USER} 2>/dev/null
    fi
    
    systemctl daemon-reload
    
    clear
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${PLAIN}"
    echo -e "${GREEN} Wait 定制版 qBittorrent 已完全卸载！${PLAIN}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${PLAIN}"
}

# 显示菜单
show_menu() {
    echo -e "
    ${GREEN}Wait 定制版 qBittorrent 管理脚本${PLAIN}
    ————————————————
    ${GREEN}1.${PLAIN} 安装 qBittorrent
    ${GREEN}2.${PLAIN} 卸载 qBittorrent
    ${GREEN}0.${PLAIN} 退出脚本
    "
    echo && read -p "请输入选择 [0-2]: " num

    case "${num}" in
        1) 
            check_installed
            install_qbittorrent
            ;;
        2) 
            uninstall_qbittorrent 
            ;;
        0) 
            exit 0 
            ;;
        *) 
            echo -e "${RED}请输入正确数字 [0-2]${PLAIN}" && exit 1 
            ;;
    esac
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
    
    show_menu
}

main
exit 0

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
    
    # 定义下载链接
    MAIN_URL="https://github.com/userdocs/qbittorrent-nox-static/releases/download/release-4.3.8_v1.2.14/x86_64-cmake-qbittorrent-nox"
    PROXY_URL="https://ghproxy.com/${MAIN_URL}"
    
    # 尝试主链接下载
    echo -e "${YELLOW}尝试从主链接下载...${PLAIN}"
    if ! wget --no-check-certificate --show-progress -q -O qbittorrent-nox "${MAIN_URL}"; then
        echo -e "${YELLOW}主链接下载失败，尝试代理下载...${PLAIN}"
        if ! wget --no-check-certificate --show-progress -q -O qbittorrent-nox "${PROXY_URL}"; then
            echo -e "${RED}下载失败！尝试备用链接...${PLAIN}"
            # 备用链接
            BACKUP_URL="https://cdn.jsdelivr.net/gh/userdocs/qbittorrent-nox-static@release-4.3.8_v1.2.14/x86_64-cmake-qbittorrent-nox"
            if ! wget --no-check-certificate --show-progress -q -O qbittorrent-nox "${BACKUP_URL}"; then
                echo -e "${RED}所有下载尝试均失败，请检查网络连接！${PLAIN}"
                exit 1
            fi
        fi
    fi
    
    # 验证下载文件
    if [ ! -f "qbittorrent-nox" ] || [ ! -s "qbittorrent-nox" ]; then
        echo -e "${RED}下载文件不存在或大小为0，安装失败！${PLAIN}"
        exit 1
    fi
    
    chmod +x qbittorrent-nox
    echo -e "${GREEN}下载完成！${PLAIN}"

    show_progress 2 "创建用户"
    if ! id "${USERNAME}" >/dev/null 2>&1; then
        useradd -r -m -s /bin/false ${USERNAME}
    fi

    show_progress 2 "配置服务"
    
    # 创建密码更新脚本
    PASSWORD_UPDATE_SCRIPT="/usr/local/bin/update_qbittorrent_password.sh"

    cat > ${PASSWORD_UPDATE_SCRIPT} << EOF
#!/bin/bash

USERNAME="${USERNAME}"
PASSWORD="${PASSWORD}"
CONFIG_FILE="/home/\${USERNAME}/.config/qBittorrent/qBittorrent.conf"

# 等待配置文件存在
for i in {1..30}; do
    if [ -f "\${CONFIG_FILE}" ]; then
        break
    fi
    sleep 1
done

# 生成密码哈希
PASSWORD_HASH=\$(echo -n "\${USERNAME}:qBittorrent:\${PASSWORD}" | md5sum | cut -d ' ' -f 1)

# 更新配置文件中的密码哈希
sed -i "s/WebUI\\\\Password_ha1=.*/WebUI\\\\Password_ha1=\${PASSWORD_HASH}/" \${CONFIG_FILE}

# 设置正确的权限
chown \${USERNAME}:\${USERNAME} \${CONFIG_FILE}
chmod 600 \${CONFIG_FILE}
EOF

    chmod +x ${PASSWORD_UPDATE_SCRIPT}
        # 创建服务文件
    cat > /etc/systemd/system/qbittorrent-nox@.service << EOF
[Unit]
Description=qBittorrent-nox service for %i
After=network.target

[Service]
Type=forking
User=%i
ExecStart=/usr/local/bin/qbittorrent-nox -d --webui-port=${WEBUI_PORT}
ExecStartPost=/usr/local/bin/update_qbittorrent_password.sh
Restart=always
LimitNOFILE=1048576
LimitNPROC=infinity
TasksMax=infinity

[Install]
WantedBy=multi-user.target
EOF

    # 先停止可能运行的服务
    systemctl stop qbittorrent-nox@${USERNAME} 2>/dev/null
    sleep 2

    # 确保目录存在并设置权限
    mkdir -p /home/${USERNAME}/.config/qBittorrent
    mkdir -p /home/${USERNAME}/downloads
    mkdir -p /home/${USERNAME}/downloads/temp
    mkdir -p /home/${USERNAME}/.config/qBittorrent/logs
    chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}
    chmod 700 /home/${USERNAME}/.config/qBittorrent

    # 生成密码哈希
    PASSWORD_HASH=$(echo -n "${USERNAME}:qBittorrent:${PASSWORD}" | md5sum | cut -d ' ' -f 1)
    
    # 配置文件路径
    CONFIG_FILE="/home/${USERNAME}/.config/qBittorrent/qBittorrent.conf"

    # 生成配置文件
    cat > ${CONFIG_FILE} << EOF
[Application]
FileLogger\Enabled=true
FileLogger\Path=/home/${USERNAME}/.config/qBittorrent/logs

[BitTorrent]
Session\DefaultSavePath=/home/${USERNAME}/downloads
Session\Port=${PORT_MIN}
Session\TempPath=/home/${USERNAME}/downloads/temp

[LegalNotice]
Accepted=true

[Preferences]
Connection\PortRangeMin=${PORT_MIN}
General\Locale=zh
WebUI\Address=*
WebUI\AlternativeUIEnabled=false
WebUI\AuthSubnetWhitelistEnabled=false
WebUI\CSRFProtection=false
WebUI\ClickjackingProtection=false
WebUI\LocalHostAuth=true
WebUI\Port=${WEBUI_PORT}
WebUI\RootFolder=
WebUI\ServerDomains=*
WebUI\Username=${USERNAME}
WebUI\Password_ha1=${PASSWORD_HASH}
EOF

    # 设置配置文件权限
    chown ${USERNAME}:${USERNAME} ${CONFIG_FILE}
    chmod 600 ${CONFIG_FILE}

    # 启动服务
    systemctl daemon-reload
    systemctl enable qbittorrent-nox@${USERNAME}
    systemctl start qbittorrent-nox@${USERNAME}

    # 等待服务启动
    echo -e "${YELLOW}等待服务启动...${PLAIN}"
    sleep 30  # 增加等待时间到30秒

    # 检查服务状态
    if ! systemctl is-active --quiet qbittorrent-nox@${USERNAME}; then
        echo -e "${RED}服务启动失败，请检查日志：${PLAIN}"
        journalctl -u qbittorrent-nox@${USERNAME} -n 50 --no-pager
        exit 1
    fi
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
    rm -f /usr/local/bin/update_qbittorrent_password.sh
    rm -f /etc/systemd/system/qbittorrent-nox@.service
    
    show_progress 2 "清理配置"
    echo -e "${BLUE}是否删除配置文件和下载目录？[y/n]: ${PLAIN}"
    read choice
    if [[ $choice == "y" || $choice == "Y" ]]; then
        rm -rf /home/${DEFAULT_USER}/.config/qBittorrent
        rm -rf /home/${DEFAULT_USER}/.local/share/data/qBittorrent
        rm -rf /home/${DEFAULT_USER}/downloads
    fi
    
    show_progress 2 "删除用户"
    echo -e "${BLUE}是否删除用户 ${DEFAULT_USER}？[y/n]: ${PLAIN}"
    read choice
    if [[ $choice == "y" || $choice == "Y" ]]; then
        userdel -r ${DEFAULT_USER} 2>/dev/null
    fi
    
    systemctl daemon-reload
    
    clear
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${PLAIN}"
    echo -e "${GREEN} Wait 定制版 qBittorrent 已完全卸载！${PLAIN}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${PLAIN}"
}

# 安装和配置函数
install_and_configure() {
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

# 显示菜单
show_menu() {
    echo -e "
    ${GREEN}Wait 定制版 qBittorrent 管理脚本${PLAIN}
    ————————————————
    ${GREEN}1.${PLAIN} 安装/更新 qBittorrent
    ${GREEN}2.${PLAIN} 卸载 qBittorrent
    ${GREEN}0.${PLAIN} 退出脚本
    "
    echo && read -p "请输入选择 [0-2]: " num

    case "${num}" in
        1) 
            check_installed
            install_and_configure 
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

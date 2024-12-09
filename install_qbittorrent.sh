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
    local width=20  # 减少宽度使进度条更快
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
    
    # 创建服务文件
    cat > /etc/systemd/system/qbittorrent-nox@.service << EOF
[Unit]
Description=qBittorrent-nox service for %i
After=network.target

[Service]
Type=simple
User=%i
ExecStart=/usr/local/bin/qbittorrent-nox
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

    systemctl daemon-reload

    # 生成密码哈希（使用 qBittorrent 的标准格式）
    PASSWORD_HASH=$(echo -n "${USERNAME}:qBittorrent:${PASSWORD}" | md5sum | cut -d ' ' -f 1)
    
    # 配置文件
    CONFIG_FILE="/home/${USERNAME}/.config/qBittorrent/qBittorrent.conf"
    
    # 确保目录存在
    mkdir -p /home/${USERNAME}/.config/qBittorrent
    mkdir -p /home/${USERNAME}/downloads
    mkdir -p /home/${USERNAME}/downloads/temp
    
    # 生成配置文件
    cat > ${CONFIG_FILE} << EOF
[AutoRun]
enabled=false

[BitTorrent]
Session\DefaultSavePath=/home/${USERNAME}/downloads
Session\Port=${PORT_MIN}
Session\TempPath=/home/${USERNAME}/downloads/temp

[LegalNotice]
Accepted=true

[Meta]
MigrationVersion=4

[Network]
Cookies=@Invalid()

[Preferences]
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
    # 设置权限
    chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}
    chmod 700 /home/${USERNAME}/.config/qBittorrent
    chmod 600 ${CONFIG_FILE}

    # 启动服务
    systemctl enable qbittorrent-nox@${USERNAME}
    systemctl start qbittorrent-nox@${USERNAME}

    # 等待服务完全启动
    echo -e "${YELLOW}等待服务启动...${PLAIN}"
    sleep 15

    # 验证配置文件
    echo -e "${CYAN}验证配置文件...${PLAIN}"
    if [ -f "${CONFIG_FILE}" ]; then
        echo -e "${GREEN}配置文件存在${PLAIN}"
        
        # 检查关键配置项
        USERNAME_CHECK=$(grep "WebUI\\\\Username" ${CONFIG_FILE} | cut -d= -f2)
        PASSWORD_CHECK=$(grep "WebUI\\\\Password_ha1" ${CONFIG_FILE} | cut -d= -f2)
        
        echo -e "${YELLOW}检查配置：${PLAIN}"
        echo -e "用户名设置：${USERNAME_CHECK}"
        echo -e "密码哈希：${PASSWORD_CHECK}"
        echo -e "预期密码哈希：${PASSWORD_HASH}"
        
        if [ "${USERNAME_CHECK}" = "${USERNAME}" ] && [ "${PASSWORD_CHECK}" = "${PASSWORD_HASH}" ]; then
            echo -e "${GREEN}配置文件验证成功${PLAIN}"
        else
            echo -e "${RED}配置文件验证失败${PLAIN}"
            echo -e "${YELLOW}配置文件内容：${PLAIN}"
            cat ${CONFIG_FILE}
            exit 1
        fi
    else
        echo -e "${RED}配置文件不存在${PLAIN}"
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

# 安装和配置函数
install_and_configure() {
    get_user_input
    install_qbittorrent
    optimize_system

    # 获取公网 IP
    IP=$(curl -s ip.sb)
    
    # 验证服务状态
    if ! systemctl is-active --quiet qbittorrent-nox@${USERNAME}; then
        echo -e "${RED}服务未能正常启动，请检查日志：${PLAIN}"
        journalctl -u qbittorrent-nox@${USERNAME} -n 50
        exit 1
    fi
    
    # 验证登录
    echo -e "${YELLOW}验证登录...${PLAIN}"
    LOGIN_TEST=$(curl -s -i --header "Referer: http://${IP}:${WEBUI_PORT}" \
                        --data "username=${USERNAME}&password=${PASSWORD}" \
                        "http://${IP}:${WEBUI_PORT}/api/v2/auth/login")
    
    if echo "$LOGIN_TEST" | grep -q "Ok."; then
        echo -e "${GREEN}登录验证成功！${PLAIN}"
        echo -e "${GREEN}用户名: ${USERNAME}${PLAIN}"
        echo -e "${GREEN}密码: ${PASSWORD}${PLAIN}"
    else
        echo -e "${RED}登录验证失败！${PLAIN}"
        echo -e "${YELLOW}服务可能需要更多时间启动，或配置有误${PLAIN}"
        echo -e "${YELLOW}请检查日志：${PLAIN}"
        journalctl -u qbittorrent-nox@${USERNAME} -n 50
        
        echo -e "${YELLOW}是否仍要继续？[y/n]${PLAIN}"
        read -p "" choice
        if [[ $choice != "y" && $choice != "Y" ]]; then
            exit 1
        fi
    fi
    
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

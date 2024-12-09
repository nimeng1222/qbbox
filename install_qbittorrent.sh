#!/bin/bash

# 脚本名称: install_qbittorrent.sh
# 描述: 安装并配置 qBittorrent 的自动化脚本
# 创建日期: 2024-03-21

# 设置错误时退出
set -e

# 默认值
QB_VERSION="4.3.8"
LT_VERSION="v1.2.14"
WEBUI_PORT="12311"
PORT_MIN="55000"

# 获取用户输入
get_user_input() {
    # 用户名
    while true; do
        read -p "请输入用户名 (仅允许字母和数字): " USERNAME
        if [[ $USERNAME =~ ^[a-zA-Z0-9]+$ ]]; then
            break
        else
            echo "错误: 用户名只能包含字母和数字"
        fi
    done

    # 密码
    while true; do
        read -s -p "请输入密码 (至少6个字符): " PASSWORD
        echo
        if [[ ${#PASSWORD} -ge 6 ]]; then
            read -s -p "请再次输入密码: " PASSWORD2
            echo
            if [[ "$PASSWORD" == "$PASSWORD2" ]]; then
                break
            else
                echo "错误: 两次输入的密码不匹配"
            fi
        else
            echo "错误: 密码长度必须至少为6个字符"
        fi
    done

    # WebUI端口
    while true; do
        read -p "请输入 WebUI 端口 (默认: 12311): " input_port
        if [[ -z "$input_port" ]]; then
            break
        elif [[ "$input_port" =~ ^[0-9]+$ ]] && [ "$input_port" -ge 1024 ] && [ "$input_port" -le 65535 ]; then
            WEBUI_PORT=$input_port
            break
        else
            echo "错误: 请输入有效的端口号 (1024-65535)"
        fi
    done

    # 确认信息
    echo -e "\n请确认以下信息:"
    echo "用户名: $USERNAME"
    echo "WebUI端口: $WEBUI_PORT"
    read -p "是否继续? (y/n): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo "安装已取消"
        exit 1
    fi
}

# 主函数
main() {
    # 获取用户输入
    get_user_input

    # 切换到 root 目录
    cd /root

    # 安装 Seedbox
    echo "开始安装 Seedbox..."
    bash <(wget -qO- https://raw.githubusercontent.com/SAGIRIxr/Dedicated-Seedbox/main/Install.sh) \
        -u "${USERNAME}" \
        -p "${PASSWORD}" \
        -c 1024 \
        -q "${QB_VERSION}" \
        -l "${LT_VERSION}" \
        -x

    # 安装额外工具
    echo "安装额外工具..."
    apt install -y curl htop vnstat

    # 停止和禁用 qBittorrent 服务
    echo "配置 qBittorrent 服务..."
    systemctl stop "qbittorrent-nox@${USERNAME}"
    systemctl disable "qbittorrent-nox@${USERNAME}"

    # 调整文件系统预留空间
    echo "调整文件系统设置..."
    tune2fs -m 1 $(df -h / | awk 'NR==2 {print $1}')

    # 配置 qBittorrent
    echo "配置 qBittorrent 设置..."
    CONFIG_FILE="/home/${USERNAME}/.config/qBittorrent/qBittorrent.conf"
    
    # 等待配置文件创建
    while [ ! -f "${CONFIG_FILE}" ]; do
        sleep 1
    done

    # 确保 [Preferences] 部分存在
    if ! grep -q "\[Preferences\]" "${CONFIG_FILE}"; then
        echo -e "\n[Preferences]" >> "${CONFIG_FILE}"
    fi

    # 修改配置
    sed -i '/^Advanced\\DiskCache=/d' "${CONFIG_FILE}"  # 删除已存在的磁盘缓存设置
    sed -i '/\[Preferences\]/a Advanced\\DiskCache=-1' "${CONFIG_FILE}"
    
    sed -i "s/WebUI\\\\Port=[0-9]*/WebUI\\\\Port=${WEBUI_PORT}/" "${CONFIG_FILE}"
    sed -i "s/Connection\\\\PortRangeMin=[0-9]*/Connection\\\\PortRangeMin=${PORT_MIN}/" "${CONFIG_FILE}"
    sed -i '/\[Preferences\]/a General\\Locale=zh' "${CONFIG_FILE}"
    sed -i '/\[Preferences\]/a Downloads\\PreAllocation=false' "${CONFIG_FILE}"
    sed -i '/\[Preferences\]/a WebUI\\CSRFProtection=false' "${CONFIG_FILE}"

    # 添加开机自启动并重启
    echo "配置开机自启动..."
    echo -e "\nsystemctl enable qbittorrent-nox@${USERNAME} && reboot" >> /root/BBRx.sh

    # 显示安装信息
    echo -e "\n安装完成! 请记住以下信息:"
    echo "用户名: $USERNAME"
    echo "WebUI端口: $WEBUI_PORT"
    echo "WebUI访问地址: http://服务器IP:${WEBUI_PORT}"

    # 计划重启
    echo -e "\n系统将在 1 分钟后重启..."
    shutdown -r +1
}

# 检查是否以 root 权限运行
if [ "$EUID" -ne 0 ]; then 
    echo "请使用 root 权限运行此脚本"
    exit 1
fi

# 运行主函数
main

exit 0

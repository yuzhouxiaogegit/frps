#!/bin/sh
# 警告：脚本已切换为 POSIX Shell (sh) 兼容模式。

# 设置严格模式 (POSIX 兼容):
set -e    # 任何命令失败（非零退出状态）立即退出脚本 (errexit)
set -u    # 尝试使用未设置的变量时报错退出 (nounset)

# ==================================================
#	System Required: CentOS 7/8, Debian, Ubuntu (Systemd)
#	Description: frp 服务端安装脚本 (TOML兼容版)
#	Version: 2.0 
#	Author: 宇宙小哥
# 	Github：https://github.com/yzhouxiaogegit/frps
#
#	Copyright (C) 2025 by 宇宙小哥 (yuzhouxiaogegit). All rights reserved.
#
#	License: MIT License (推荐)
#	本脚本以 MIT 许可发布。
# ==================================================

# 颜色定义
Green_font_prefix="\033[32m"
Red_font_prefix="\033[31m"
Yellow_font_prefix="\033[33m"
Font_color_suffix="\033[0m"
Info="${Green_font_prefix}[信息]${Font_color_suffix}"
Error="${Red_font_prefix}[错误]${Font_color_suffix}"
Tip="${Yellow_font_prefix}[注意]${Font_color_suffix}"

# 打印文字颜色方法
echoTxtColor(){
    local text="$1"
    local color_name="$2"
    
    case "$color_name" in
        red)    echo -e "${Red_font_prefix}${text}${Font_color_suffix}" ;;
        green)  echo -e "${Green_font_prefix}${text}${Font_color_suffix}" ;;
        yellow) echo -e "${Yellow_font_prefix}${text}${Font_color_suffix}" ;;
        *)      echo "$text" ;;
    esac
}

# ----------------------------------------------------
# 核心函数：安装所有依赖工具和运行时库
# ----------------------------------------------------

install_all_deps() {
    echo -e "${Info} 正在检查并安装所有必需的系统工具和依赖库..."
    local INSTALL_CMD=""
    local UPDATE_CMD=""
    local DEPS_LIST=""

    if command -v apt >/dev/null 2>&1; then
        # Debian/Ubuntu
        UPDATE_CMD="apt update -qq"
        INSTALL_CMD="apt install -y"
        # 依赖列表：OpenSSL库、下载工具、网络工具、防火墙工具
        DEPS_LIST="libssl3 libssl1.1-dev openssl wget curl net-tools iproute2 firewalld ufw"
    elif command -v yum >/dev/null 2>&1; then
        # CentOS/RHEL (旧)
        INSTALL_CMD="yum install -y"
        DEPS_LIST="openssl wget curl net-tools iproute2 firewalld"
    elif command -v dnf >/dev/null 2>&1; then
        # Fedora/CentOS (新)
        INSTALL_CMD="dnf install -y"
        DEPS_LIST="openssl wget curl net-tools iproute2 firewalld"
    else
        echo -e "${Error} 无法识别的 Linux 发行版或包管理器，请手动安装依赖。"
        return 0
    fi

    if [ -n "$UPDATE_CMD" ]; then
        echo -e "${Info} 正在更新包列表..."
        $UPDATE_CMD >/dev/null 2>&1 || true
    fi

    echo -e "${Info} 正在安装核心依赖 (可能需要一些时间)..."
    $INSTALL_CMD $DEPS_LIST >/dev/null 2>&1 || true
    
    echo -e "${Info} 所有必需系统依赖检查/安装完成。"
}

# ----------------------------------------------------
# 新增函数：智能开放防火墙端口
# ----------------------------------------------------

open_firewall_port() {
    local port="$1"
    echo -e "${Info} 正在尝试自动开放 Bind Port (${port}) TCP 端口..."

    if command -v firewall-cmd >/dev/null 2>&1; then
        echo -e "${Info} 检测到 firewalld，正在配置..."
        # 尝试启动 firewalld 如果它没有运行
        if ! systemctl is-active --quiet firewalld; then
            echo -e "${Tip} firewalld 服务未运行，尝试启动并启用..."
            systemctl start firewalld >/dev/null 2>&1 || true
            systemctl enable firewalld >/dev/null 2>&1 || true
        fi
        
        # 实际开放端口
        firewall-cmd --zone=public --add-port="${port}/tcp" --permanent >/dev/null 2>&1
        firewall-cmd --reload >/dev/null 2>&1
        echo -e "${Green_font_prefix}firewalld 开放端口 ${port} 成功。${Font_color_suffix}"
    elif command -v ufw >/dev/null 2>&1; then
        echo -e "${Info} 检测到 UFW (Uncomplicated Firewall)，正在配置..."
        # 尝试启用 UFW 如果它未启用
        if ! ufw status | grep -q "active"; then
            echo -e "${Tip} UFW 未启用，尝试启用..."
            ufw default allow outgoing >/dev/null 2>&1
            ufw default deny incoming >/dev/null 2>&1
            ufw enable -y >/dev/null 2>&1 || true
        fi

        ufw allow "${port}/tcp" >/dev/null 2>&1
        echo -e "${Green_font_prefix}UFW 开放端口 ${port} 成功。${Font_color_suffix}"
    else
        echo -e "${Tip} 未检测到 firewalld 或 UFW，请手动开放 Bind Port ${port} 端口。"
    fi
}

# ----------------------------------------------------
# 脚本其余流程函数 (保持一致)
# ----------------------------------------------------

get_latest_frp_version() {
    echo -e "${Info} 正在获取 frp 最新版本号..."
    local release_info=""
    
    if command -v curl >/dev/null 2>&1; then
        release_info=$(curl -s "https://api.github.com/repos/fatedier/frp/releases/latest")
        local tag_name=$(echo "$release_info" | grep '"tag_name":' | head -n 1 | cut -d '"' -f 4)
    else
        local redirect_url=$(wget -qO- --server-response "https://github.com/fatedier/frp/releases/latest" 2>&1 | grep 'Location:' | tail -n 1)
        local tag_name=$(echo "$redirect_url" | awk -F'/' '{print $NF}')
    fi

    if [ -z "$tag_name" ]; then
        echoTxtColor "错误: 无法获取 frp 最新版本号，请检查网络或 GitHub 状态。" "red"
        exit 1
    fi
    
    getFrpV="${tag_name#v}"
    echo -e "${Info} 检测到最新版本: v${getFrpV}"
}

check_arch() {
    local arch
    arch=$(uname -m)
    case "$arch" in
        "x86_64" | "amd64")
            bit="amd64"
            ;;
        "aarch64" | "arm64")
            bit="arm64"
            ;;
        *)
            echoTxtColor "错误: 暂不支持当前系统架构 ${arch}。" "red"
            exit 1
            ;;
    esac
    FRPS_FILE="frp_${getFrpV}_linux_${bit}.tar.gz"
    FRPS_DIR="frp_${getFrpV}_linux_${bit}"
}

generate_random_token() {
    if command -v openssl >/dev/null 2>&1; then
        openssl rand -hex 8 | tr -d '\n'
    else
        cat /proc/sys/kernel/random/uuid
    fi
}


# ----------------------------------------------------
# 脚本主执行流程
# ----------------------------------------------------

install_all_deps # 自动安装所有依赖，包括防火墙工具
get_latest_frp_version
check_arch

echo ""
echoTxtColor "--- frps 服务端配置输入 (作者: 宇宙小哥 | v${getFrpV}) ---" "green"

# 用户输入和默认值处理 (POSIX 兼容)
IFS= read -r -p "请输入 Bind Port 监听端口 (默认：7000):" bind_port
IFS= read -r -p "请输入 Vhost HTTP Port 端口 (默认：8080):" vhost_http_port
IFS= read -r -p "请输入 Vhost HTTPS Port 端口 (默认：4430):" vhost_https_port

: "${bind_port:=7000}"
: "${vhost_http_port:=8080}"
: "${vhost_https_port:=4430}"

# ----------------------------------------------------
# 1. 下载和安装
# ----------------------------------------------------

echo ""
echo -e "${Info} 开始下载和安装 frps..."

# 使用 wget 或 curl 下载 frp
if command -v wget >/dev/null 2>&1; then
    DOWNLOAD_CMD="wget --no-check-certificate -O"
elif command -v curl >/dev/null 2>&1; then
    DOWNLOAD_CMD="curl -fsSL -o"
else
    echoTxtColor "致命错误: 下载工具 (wget/curl) 安装失败，无法继续。" "red"
    exit 1
fi

FRPS_DOWNLOAD_URL="https://github.com/fatedier/frp/releases/download/v${getFrpV}/${FRPS_FILE}"
$DOWNLOAD_CMD "/tmp/${FRPS_FILE}" "$FRPS_DOWNLOAD_URL"
echo -e "${Info} 下载完成。"

# 解压 frp 到临时目录
tar -xzvf "/tmp/${FRPS_FILE}" -C /tmp

echo -e "${Info} 正在删除旧安装目录并创建新目录..."
rm -rf /usr/local/frps/
mkdir -p /usr/local/frps

mv "/tmp/${FRPS_DIR}/frps" /usr/local/frps/
mv "/tmp/${FRPS_DIR}/frps.toml" /usr/local/frps/frps.example.toml 

rm -rf "/tmp/${FRPS_FILE}" "/tmp/${FRPS_DIR}"
echo -e "${Info} 文件移动和清理完成。"

chmod +x /usr/local/frps/frps
echo -e "${Info} frps 可执行文件权限设置完成。"

# ----------------------------------------------------
# 2. 生成配置和注册服务
# ----------------------------------------------------

token=$(generate_random_token)

echo -e "${Info} 正在生成 frps.toml 配置文件..."
cat > /usr/local/frps/frps.toml <<-EOT
[common] # 增强兼容性
bindPort = ${bind_port}
auth.token = "${token}" 
vhostHTTPPort = ${vhost_http_port}
vhostHTTPSPort = ${vhost_https_port}
EOT

echo -e "${Info} 正在创建 systemd 服务文件..."
cat > /etc/systemd/system/frps.service <<-EOF
[Unit]
Description = frps service
After = network.target syslog.target
Wants = network.target

[Service]
Type = simple
ExecStart = /usr/local/frps/frps -c /usr/local/frps/frps.toml

# 启动失败时自动重启
Restart = always
RestartSec = 10s

[Install]
WantedBy = multi-user.target
EOF

# ----------------------------------------------------
# 3. 启动和启用服务
# ----------------------------------------------------

echo -e "${Info} 正在重载并启动 frps 服务..."
systemctl stop frps.service >/dev/null 2>&1 || true

systemctl daemon-reload
systemctl enable frps.service >/dev/null 2>&1
systemctl start frps.service

# 检查服务状态
if systemctl is-active --quiet frps.service; then
    echoTxtColor "frps 服务启动成功！" "green"
else
    # 增强的错误诊断提示
    echoTxtColor "frps 服务启动失败！" "red"
    echoTxtColor "---------------------------------------------------------" "red"
    echoTxtColor "失败原因诊断：" "yellow"
    echoTxtColor "1. 端口冲突 (最常见)：以下配置端口可能已被占用，请检查并手动修改 frps.toml 文件或停止占用程序。" "yellow"
    echo -e "\t- Bind Port (Frp主通信): ${bind_port}"
    echo -e "\t- HTTP Port (Web服务): ${vhost_http_port}"
    echo -e "\t- HTTPS Port (Web服务): ${vhost_https_port}"
    echoTxtColor "   💡 检查命令：${Green_font_prefix}netstat -tuln | grep [端口号]${Font_color_suffix}" "yellow"
    echoTxtColor "2. 详细日志：请运行以下命令查看详细的程序退出原因：" "yellow"
    echo -e "\t${Green_font_prefix}journalctl -xeu frps.service${Font_color_suffix}"
    echoTxtColor "---------------------------------------------------------" "red"
    systemctl status frps.service --no-pager
    exit 1
fi

# *********** 新增步骤：自动开放 Bind Port ***********
open_firewall_port "${bind_port}"
# *****************************************************

# ----------------------------------------------------
# 4. 打印配置信息
# ----------------------------------------------------

echo -e "\n${Green_font_prefix}=== frps 服务端配置信息 ===${Font_color_suffix}\n"

echo -e "\t监听端口 (bindPort) \t\t= ${bind_port} (TCP 端口已尝试自动开放 ✅)
\tHTTP 端口 (vhostHTTPPort) \t= ${vhost_http_port}
\tHTTPS 端口 (vhostHTTPSPort) \t= ${vhost_https_port}
\t连接令牌 (auth.token) \t\t= ${token}\n

\t配置文件路径：\t\t/usr/local/frps/frps.toml
\t配置示例路径：\t\t/usr/local/frps/frps.example.toml
"

echoTxtColor "frp安装成功！" "green"
echoTxtColor "请手动开放 ${vhost_http_port}, ${vhost_https_port} 端口后进行使用 (Bind Port ${bind_port} 已自动处理)。" "yellow"
echo "--- 脚本结束 (作者: 宇宙小哥) ---"

exit 0

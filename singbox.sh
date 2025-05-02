#!/bin/bash

# ============= 全局变量 =============
SING_BOX_VERSION="v1.12.0-alpha.10"  # Sing-box 版本
INSTALL_DIR="/etc/sing-box"          # 安装目录
CONF_DIR="$INSTALL_DIR/conf"         # 配置目录
BIN_DIR="$INSTALL_DIR/bin"           # 可执行文件目录
LOG_FILE="/var/log/sing-box.log"     # 日志文件
SERVICE_NAME="sing-box"              # 服务名称
CERT_DIR="/home/ssl"                # 证书目录

# 颜色定义
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"
PLAIN="\033[0m"

# 安装依赖
apt update
apt install -y sudo curl wget

# 确保安装目录存在
mkdir -p /etc/sing-box/conf

# ============= 辅助函数 =============
# 打印彩色文本
print_color() {
    local color=$1
    local text=$2
    echo -e "${color}${text}${PLAIN}"
}

# 获取系统架构
get_arch() {
    local arch=$(uname -m)
    case $arch in
        x86_64)
            echo "amd64"
            ;;
        aarch64)
            echo "arm64"
            ;;
        *)
            print_color $RED "不支持的架构: $arch"
            exit 1
            ;;
    esac
}

# ============= 安装函数 =============
# 检查Sing-box版本
check_sing_box_version() {
    print_color $BLUE "正在检查Sing-box版本..."
    if [[ -x "$BIN_DIR/sing-box" ]]; then
        local current_version=$("$BIN_DIR/sing-box" version 2>/dev/null | grep -oP 'sing-box version \K[^ ]+' || echo "unknown")
        print_color $BLUE "当前版本: $current_version, 目标版本: ${SING_BOX_VERSION#v}"
        if [[ "$current_version" == "${SING_BOX_VERSION#v}" ]]; then
            print_color $GREEN "已安装Sing-box ${current_version}，无需重新下载。"
            return 0  # 版本匹配，无需安装
        else
            print_color $YELLOW "已安装Sing-box版本 ${current_version}，需要更新到 ${SING_BOX_VERSION#v}"
            return 1  # 版本不匹配，需要安装
        fi
    else
        print_color $YELLOW "未安装Sing-box，将进行安装..."
    fi
    return 1  # 未安装，需要安装
}

# 安装 Sing-box
install_sing_box() {
    if check_sing_box_version; then
        return 0
    fi

    print_color $BLUE "正在检测系统架构..."
    local arch=$(get_arch)
    print_color $BLUE "系统架构: $arch"

    local file_url="https://github.com/SagerNet/sing-box/releases/download/$SING_BOX_VERSION/sing-box-${SING_BOX_VERSION#v}-linux-$arch.tar.gz"
    print_color $BLUE "下载URL: $file_url"

    local temp_dir=$(mktemp -d)
    print_color $BLUE "临时目录: $temp_dir"

    print_color $BLUE "正在准备下载 Sing-box $SING_BOX_VERSION..."
    if ! wget --timeout=15 --tries=3 "$file_url" -O "$temp_dir/sing-box.tar.gz" 2>&1; then
        print_color $YELLOW "通过GitHub下载失败，尝试备用方法..."
        if command -v curl &> /dev/null; then
            print_color $BLUE "尝试使用curl下载..."
            if ! curl -L --connect-timeout 15 --retry 3 "$file_url" -o "$temp_dir/sing-box.tar.gz"; then
                print_color $RED "下载失败，请检查网络连接或版本号。"
                rm -rf "$temp_dir"
                exit 1
            fi
        else
            print_color $RED "下载失败，请检查网络连接或版本号。"
            rm -rf "$temp_dir"
            exit 1
        fi
    fi

    print_color $GREEN "下载完成！正在验证文件..."
    if [[ ! -s "$temp_dir/sing-box.tar.gz" ]]; then
        print_color $RED "下载的文件为空，请重试。"
        rm -rf "$temp_dir"
        exit 1
    fi

    local downloaded_size=$(du -h "$temp_dir/sing-box.tar.gz" | cut -f1)
    print_color $GREEN "成功下载文件，大小: $downloaded_size"

    print_color $BLUE "正在解压 Sing-box..."
    mkdir -p "$temp_dir/extract"
    if ! tar -xzf "$temp_dir/sing-box.tar.gz" -C "$temp_dir/extract" --strip-components=1; then
        print_color $RED "解压失败，请检查文件。"
        rm -rf "$temp_dir"
        exit 1
    fi

    print_color $GREEN "解压完成！"
    print_color $BLUE "正在安装 Sing-box..."
    mkdir -p "$BIN_DIR"
    if ! cp "$temp_dir/extract/sing-box" "$BIN_DIR/"; then
        print_color $RED "复制文件失败。"
        rm -rf "$temp_dir"
        exit 1
    fi

    # 额外将可执行文件复制到 /usr/local/bin/
    if ! cp "$temp_dir/extract/sing-box" "/usr/local/bin/"; then
        print_color $RED "复制文件到 /usr/local/bin/ 失败。"
        rm -rf "$temp_dir"
        exit 1
    fi

    chmod +x "$BIN_DIR/sing-box"
    chmod +x "/usr/local/bin/sing-box"
    if [[ -x "$BIN_DIR/sing-box" ]]; then
        local version=$("$BIN_DIR/sing-box" version 2>/dev/null || echo "无法获取版本信息")
        print_color $GREEN "Sing-box 安装成功！版本信息: $version"
    else
        print_color $RED "Sing-box 安装失败，无法执行 $BIN_DIR/sing-box"
        exit 1
    fi

    rm -rf "$temp_dir"
    print_color $GREEN "清理临时文件完成"
}

# 创建 config.json 配置文件
create_config() {
    print_color $BLUE "正在检查配置文件..."
    if [[ -f "$INSTALL_DIR/config.json" ]]; then
        print_color $YELLOW "配置文件已存在，跳过创建。"
        return 0
    fi

    print_color $BLUE "正在创建配置文件..."
    mkdir -p "$INSTALL_DIR"
    cat > "$INSTALL_DIR/config.json" <<EOF
{
  "log": {
    "level": "info",
    "output": "/var/log/sing-box.log"
  },
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct-outbound"
    }
  ]
}
EOF
    print_color $GREEN "配置文件创建完成！"
}

# 创建系统服务
create_service() {
    print_color $BLUE "正在检查系统服务..."
    if [[ -f /etc/systemd/system/$SERVICE_NAME.service ]]; then
        print_color $YELLOW "服务文件已存在，跳过创建。"
        return 0
    fi

    print_color $BLUE "正在创建系统服务..."
    cat > /etc/systemd/system/$SERVICE_NAME.service <<EOF
[Unit]
Description=Sing-box Proxy Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$BIN_DIR/sing-box run -c $INSTALL_DIR/config.json -C $CONF_DIR
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
    sudo systemctl daemon-reload
    sudo systemctl enable $SERVICE_NAME
    print_color $GREEN "系统服务创建完成！"
}

# 安装SSL证书 - 从指定URL下载
install_ssl() {
    print_color $BLUE "正在检查SSL证书..."
    if [[ -f "$CERT_DIR/public.pem" ]] && [[ -f "$CERT_DIR/private.key" ]]; then
        print_color $YELLOW "证书已存在，跳过安装。"
        return 0
    fi

    print_color $BLUE "正在创建 $CERT_DIR 文件夹并下载证书和密钥..."
    sudo mkdir -p "$CERT_DIR"

    print_color $BLUE "正在下载 public.pem..."
    sudo wget -q --show-progress "public.pem链接" -O "$CERT_DIR/public.pem" || {
        print_color $RED "下载 public.pem 失败，请检查链接。"
        exit 1
    }

    print_color $BLUE "正在下载 private.key..."
    sudo wget -q --show-progress "private.key链接" -O "$CERT_DIR/private.key" || {
        print_color $RED "下载 private.key 失败，请检查链接。"
        exit 1
    }

    # 确保权限正确
    sudo chmod 600 "$CERT_DIR/private.key"
    sudo chmod 644 "$CERT_DIR/public.pem"

    print_color $GREEN "SSL证书下载完成！"
    return 0
}

# ============= 创建 sb 文件 =============
create_sb_file() {
  local sb_file="/usr/local/bin/sb"

  cat > "$sb_file" <<EOF
#!/bin/bash

# 颜色定义
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"
PLAIN="\033[0m"

# 服务名称
SERVICE_NAME="sing-box"

# 定义彩色打印函数
print_color() {
    local color=\$1
    local text=\$2
    echo -e "\${color}\${text}\${PLAIN}"
}

# 显示菜单
show_menu() {
    echo ""
    print_color \$YELLOW "Sing-box 控制菜单"
    echo "1. 启动 Sing-box"
    echo "2. 关闭 Sing-box"
    echo "3. 重启 Sing-box"
    echo "4. 查看 Sing-box 状态"
    echo "5. 退出"
    echo ""
    read -p "请选择 (1-5): " choice
}

# 执行操作
execute_action() {
    case \$choice in
        1)
            sudo systemctl start "\$SERVICE_NAME"
            if [ \$? -eq 0 ]; then
                print_color \$GREEN "Sing-box 启动成功！"
            else
                print_color \$RED "Sing-box 启动失败！"
            fi
            ;;
        2)
            sudo systemctl stop "\$SERVICE_NAME"
            if [ \$? -eq 0 ]; then
                print_color \$GREEN "Sing-box 关闭成功！"
            else
                print_color \$RED "Sing-box 关闭失败！"
            fi
            ;;
        3)
            sudo systemctl restart "\$SERVICE_NAME"
            if [ \$? -eq 0 ]; then
                print_color \$GREEN "Sing-box 重启成功！"
            else
                print_color \$RED "Sing-box 重启失败！"
            fi
            ;;
        4)
            sudo systemctl status "\$SERVICE_NAME"
            ;;
        5)
            print_color \$GREEN "退出。"
            exit 0
            ;;
        *)
            print_color \$RED "无效的选择，请重试。"
            ;;
    esac
}

# 主程序
while true; do
    show_menu
    execute_action
done
EOF

  chmod +x "$sb_file"
  print_color $GREEN "已创建 /usr/local/bin/sb 文件，并赋予执行权限。"
}

# ============= 主程序 =============

# 先执行安装
install_sing_box
create_config
create_service
install_ssl

# 创建 sb 文件
create_sb_file

print_color $GREEN "Sing-box 安装和配置完成！可以使用 'sb' 命令管理 Sing-box。"

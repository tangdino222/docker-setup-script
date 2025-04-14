#!/bin/bash
set -e

# 检测系统类型
if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    OS=$ID
    VERSION_ID=$VERSION_ID
else
    echo "无法检测操作系统类型，脚本退出。"
    exit 1
fi

echo "检测到系统: $OS $VERSION_ID"

# 检查 Docker 是否已安装
check_docker_installed() {
    if command -v docker &> /dev/null; then
        echo "Docker 已安装，准备进行升级..."
        return 0
    else
        echo "Docker 未安装，准备进行安装..."
        return 1
    fi
}

# 检查 Docker Compose 是否已安装
check_docker_compose_installed() {
    if command -v docker-compose &> /dev/null; then
        echo "Docker Compose 已安装，准备进行升级..."
        return 0
    else
        echo "Docker Compose 未安装，准备进行安装..."
        return 1
    fi
}

# 安装 Docker
install_docker() {
    echo "正在安装 Docker..."
    case "$OS" in
        debian|ubuntu)
            apt update && apt install -y ca-certificates curl gnupg
            install -m 0755 -d /etc/apt/keyrings
            curl -fsSL https://download.docker.com/linux/$OS/gpg | tee /etc/apt/keyrings/docker.asc > /dev/null
            chmod a+r /etc/apt/keyrings/docker.asc
            echo "deb [signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/$OS $VERSION_CODENAME stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
            apt update && apt install -y docker-ce docker-ce-cli containerd.io
            ;;
        centos|rhel)
            yum install -y yum-utils
            yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            yum install -y docker-ce docker-ce-cli containerd.io
            systemctl enable --now docker
            ;;
        arch)
            pacman -Sy --noconfirm docker
            systemctl enable --now docker
            ;;
        *)
            echo "不支持的操作系统: $OS"
            exit 1
            ;;
    esac
    echo "Docker 安装完成！"
}

# 升级 Docker
upgrade_docker() {
    echo "正在升级 Docker..."
    case "$OS" in
        debian|ubuntu)
            apt update && apt upgrade -y docker-ce docker-ce-cli containerd.io
            ;;
        centos|rhel)
            yum update -y docker-ce docker-ce-cli containerd.io
            ;;
        arch)
            pacman -Syu --noconfirm docker
            ;;
        *)
            echo "不支持的操作系统: $OS"
            exit 1
            ;;
    esac
    echo "Docker 升级完成！"
}

# 安装 Docker Compose
install_docker_compose() {
    echo "正在安装 Docker Compose..."
    LATEST_COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep '"tag_name"' | cut -d '"' -f 4)
    curl -L "https://github.com/docker/compose/releases/download/$LATEST_COMPOSE_VERSION/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    echo "Docker Compose 安装完成！"
}

# 升级 Docker Compose
upgrade_docker_compose() {
    echo "正在升级 Docker Compose..."
    LATEST_COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep '"tag_name"' | cut -d '"' -f 4)
    curl -L "https://github.com/docker/compose/releases/download/$LATEST_COMPOSE_VERSION/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    echo "Docker Compose 升级完成！"
}

# 执行安装或升级
check_docker_installed && upgrade_docker || install_docker
check_docker_compose_installed && upgrade_docker_compose || install_docker_compose

echo "所有操作完成！"

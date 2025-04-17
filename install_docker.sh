#!/bin/bash
set -e
export LANG=C.UTF-8

# 彩色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# 确保以 root 身份运行
if [[ "$EUID" -ne 0 ]]; then
    echo -e "${RED}请以 root 用户运行此脚本。${NC}"
    exit 1
fi

# 检测系统类型
if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    OS=$ID
    VERSION_ID=$VERSION_ID
    VERSION_CODENAME=${VERSION_CODENAME:-$(grep VERSION_CODENAME /etc/os-release | cut -d= -f2 | tr -d \")}
else
    echo -e "${RED}无法检测操作系统类型，脚本退出。${NC}"
    exit 1
fi

echo -e "${GREEN}检测到系统: $OS $VERSION_ID${NC}"

# 菜单展示
show_menu() {
    echo -e "\n${YELLOW}请选择操作:${NC}"
    echo "1) 安装/升级 Docker 和 Docker Compose"
    echo "2) 卸载 Docker 和 Docker Compose"
    echo "0) 退出脚本"
    read -p "请输入数字选择: " choice
}

check_docker_installed() {
    command -v docker &> /dev/null
}

check_docker_compose_installed() {
    command -v docker-compose &> /dev/null
}

install_docker() {
    echo -e "\n${GREEN}正在安装 Docker...${NC}"
    case "$OS" in
        debian|ubuntu)
            apt update && apt install -y ca-certificates curl gnupg
            install -m 0755 -d /etc/apt/keyrings
            curl -fsSL https://download.docker.com/linux/$OS/gpg | tee /etc/apt/keyrings/docker.asc > /dev/null
            chmod a+r /etc/apt/keyrings/docker.asc
            echo "deb [signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/$OS $VERSION_CODENAME stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
            apt update && apt install -y docker-ce docker-ce-cli containerd.io
            systemctl enable --now docker
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
            echo -e "${RED}不支持的操作系统: $OS${NC}"
            exit 1
            ;;
    esac
    echo -e "${GREEN}Docker 安装完成！${NC}"
}

uninstall_docker() {
    echo -e "\n${RED}正在卸载 Docker...${NC}"
    case "$OS" in
        debian|ubuntu)
            apt purge -y docker-ce docker-ce-cli containerd.io
            rm -rf /etc/apt/keyrings/docker.asc
            rm -rf /etc/apt/sources.list.d/docker.list
            ;;
        centos|rhel)
            yum remove -y docker-ce docker-ce-cli containerd.io
            rm -rf /etc/yum.repos.d/docker-ce.repo
            ;;
        arch)
            pacman -R --noconfirm docker
            ;;
    esac
    echo -e "${GREEN}Docker 已卸载！${NC}"
}

install_docker_compose() {
    echo -e "\n${GREEN}正在安装 Docker Compose...${NC}"
    LATEST_COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep '"tag_name"' | cut -d '"' -f 4)
    curl -L "https://github.com/docker/compose/releases/download/$LATEST_COMPOSE_VERSION/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    # 可选软链
    if ! command -v docker-compose &> /dev/null; then
        ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose 2>/dev/null || true
    fi
    echo -e "${GREEN}Docker Compose 安装完成！${NC}"
}

uninstall_docker_compose() {
    echo -e "\n${RED}正在卸载 Docker Compose...${NC}"
    rm -f /usr/local/bin/docker-compose /usr/bin/docker-compose
    echo -e "${GREEN}Docker Compose 已卸载！${NC}"
}

# 主循环
while true; do
    show_menu
    case $choice in
        1)
            check_docker_installed || install_docker
            check_docker_compose_installed || install_docker_compose
            ;;
        2)
            check_docker_installed && uninstall_docker || echo -e "${YELLOW}Docker 未安装，无需卸载${NC}"
            check_docker_compose_installed && uninstall_docker_compose || echo -e "${YELLOW}Docker Compose 未安装，无需卸载${NC}"
            ;;
        0)
            echo -e "${GREEN}已退出脚本${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}无效选择，请重新输入！${NC}"
            ;;
    esac
done

#!/bin/bash
set -e
export LANG=C.UTF-8

# 彩色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# 检查 root 权限
if [[ "$EUID" -ne 0 ]]; then
    echo -e "${RED}请使用 root 权限运行此脚本。${NC}"
    exit 1
fi

# 初始化
IS_CHINA_IP=false
API_PROXY=""

# 检测 IP 是否来自中国大陆
detect_ip_location() {
    echo -e "${YELLOW}正在检测当前 IP 归属地...${NC}"
    local country=$(curl -s https://ipinfo.io/json | grep '"country"' | cut -d '"' -f 4)
    if [[ "$country" == "CN" ]]; then
        IS_CHINA_IP=true
        API_PROXY="https://ghproxy.com/"
        echo -e "${GREEN}检测到为中国大陆 IP，将使用国内镜像与加速。${NC}"
    else
        IS_CHINA_IP=false
        API_PROXY=""
        echo -e "${YELLOW}检测到为非中国 IP，使用官方源。${NC}"
    fi
}

# 检测系统
if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    OS=$ID
    VERSION_ID=$VERSION_ID
    VERSION_CODENAME=${VERSION_CODENAME:-$(grep VERSION_CODENAME /etc/os-release | cut -d= -f2 | tr -d \")}
else
    echo -e "${RED}无法检测系统信息，退出。${NC}"
    exit 1
fi

echo -e "${GREEN}检测到系统: $OS $VERSION_ID${NC}"
detect_ip_location

# 菜单
show_menu() {
    echo -e "\n${YELLOW}请选择操作:${NC}"
    echo "1) 安装/升级 Docker、Docker Compose、Watchtower"
    echo "2) 卸载 Docker、Docker Compose、Watchtower"
    echo "0) 退出脚本"
    read -p "请输入数字选择: " choice
}

# 检查工具
check_docker_installed() {
    command -v docker &> /dev/null
}
check_docker_compose_installed() {
    command -v docker-compose &> /dev/null
}
check_watchtower_installed() {
    docker ps -a --format '{{.Names}}' | grep -q '^watchtower$'
}

# 启用国内 Docker 镜像
enable_china_mirror() {
    echo -e "${YELLOW}配置阿里云 Docker 镜像加速...${NC}"
    mkdir -p /etc/docker
    cat > /etc/docker/daemon.json <<EOF
{
  "registry-mirrors": ["https://registry.docker-cn.com", "https://mirror.aliyuncs.com"]
}
EOF
    systemctl daemon-reexec
    systemctl restart docker
    echo -e "${GREEN}镜像加速已启用${NC}"
}

# 安装 Docker
install_docker() {
    echo -e "\n${GREEN}正在安装 Docker...${NC}"
    case "$OS" in
        debian|ubuntu)
            apt update && apt install -y ca-certificates curl gnupg lsb-release
            install -m 0755 -d /etc/apt/keyrings
            curl -fsSL https://download.docker.com/linux/$OS/gpg | tee /etc/apt/keyrings/docker.asc > /dev/null
            chmod a+r /etc/apt/keyrings/docker.asc
            echo "deb [signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/$OS $VERSION_CODENAME stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
            apt update && apt install -y docker-ce docker-ce-cli containerd.io
            systemctl enable --now docker
            $IS_CHINA_IP && enable_china_mirror
            ;;
        centos|rhel)
            yum install -y yum-utils
            yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            yum install -y docker-ce docker-ce-cli containerd.io
            systemctl enable --now docker
            $IS_CHINA_IP && enable_china_mirror
            ;;
        arch)
            pacman -Sy --noconfirm docker
            systemctl enable --now docker
            $IS_CHINA_IP && enable_china_mirror
            ;;
        *)
            echo -e "${RED}暂不支持此系统: $OS${NC}"
            exit 1
            ;;
    esac
    echo -e "${GREEN}Docker 安装完成！${NC}"
}

# 卸载 Docker
uninstall_docker() {
    echo -e "\n${RED}正在卸载 Docker...${NC}"
    case "$OS" in
        debian|ubuntu)
            apt purge -y docker-ce docker-ce-cli containerd.io
            rm -rf /etc/apt/keyrings/docker.asc /etc/apt/sources.list.d/docker.list /etc/docker
            ;;
        centos|rhel)
            yum remove -y docker-ce docker-ce-cli containerd.io
            rm -rf /etc/yum.repos.d/docker-ce.repo /etc/docker
            ;;
        arch)
            pacman -R --noconfirm docker
            rm -rf /etc/docker
            ;;
    esac
    echo -e "${GREEN}Docker 已卸载${NC}"
}

# 安装 Docker Compose
install_docker_compose() {
    echo -e "\n${GREEN}正在安装 Docker Compose...${NC}"
    LATEST=$(curl -s ${API_PROXY}https://api.github.com/repos/docker/compose/releases/latest | grep '"tag_name"' | cut -d '"' -f 4)
    CURRENT=$(docker-compose version --short 2>/dev/null || echo "")

    if [[ "$CURRENT" == "$LATEST" ]]; then
        echo -e "${GREEN}Docker Compose 已是最新版：$CURRENT${NC}"
        return
    fi

    echo -e "${YELLOW}正在安装版本: $LATEST ...${NC}"
    curl -L "${API_PROXY}https://github.com/docker/compose/releases/download/${LATEST}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
    echo -e "${GREEN}Docker Compose 安装完成！${NC}"
}

# 卸载 Compose
uninstall_docker_compose() {
    echo -e "\n${RED}正在卸载 Docker Compose...${NC}"
    rm -f /usr/local/bin/docker-compose /usr/bin/docker-compose
    echo -e "${GREEN}Docker Compose 已卸载${NC}"
}

# 安装 Watchtower
install_watchtower() {
    if check_watchtower_installed; then
        echo -e "${GREEN}Watchtower 已部署${NC}"
        return
    fi
    echo -e "${GREEN}正在安装 Watchtower...${NC}"
    docker run -d \
        --name watchtower \
        --restart always \
        -v /var/run/docker.sock:/var/run/docker.sock \
        containrrr/watchtower \
        --cleanup --interval 86400
    echo -e "${GREEN}Watchtower 部署完成！（每天自动检查更新）${NC}"
}

# 卸载 Watchtower
uninstall_watchtower() {
    echo -e "${RED}正在卸载 Watchtower...${NC}"
    docker rm -f watchtower 2>/dev/null || true
    echo -e "${GREEN}Watchtower 已卸载${NC}"
}

# 主流程
while true; do
    show_menu
    case $choice in
        1)
            check_docker_installed || install_docker
            install_docker_compose
            install_watchtower
            ;;
        2)
            check_docker_installed && uninstall_docker || echo -e "${YELLOW}Docker 未安装${NC}"
            check_docker_compose_installed && uninstall_docker_compose || echo -e "${YELLOW}Docker Compose 未安装${NC}"
            check_watchtower_installed && uninstall_watchtower || echo -e "${YELLOW}Watchtower 未部署${NC}"
            ;;
        0)
            echo -e "${GREEN}已退出${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}无效选项，请重试${NC}"
            ;;
    esac
done

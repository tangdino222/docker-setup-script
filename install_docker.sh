#!/bin/bash
set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# 检测系统类型
if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    OS=$ID
    VERSION_ID=$VERSION_ID
    VERSION_CODENAME=${VERSION_CODENAME:-$(. /etc/os-release && echo "$VERSION_CODENAME")}
else
    echo -e "${RED}无法检测操作系统类型，脚本退出。${NC}"
    exit 1
fi

echo -e "${GREEN}检测到系统: $OS $VERSION_ID${NC}"

# 检测是否是中国大陆IP
is_china_ip() {
    IP=$(curl -s --max-time 5 https://ipinfo.io/ip)
    COUNTRY=$(curl -s --max-time 5 https://ipapi.co/${IP}/country_code 2>/dev/null || echo "XX")
    [[ "$COUNTRY" == "CN" ]]
}

# 使用国内镜像
setup_cn_mirrors() {
    echo -e "${YELLOW}检测到中国大陆IP，启用国内加速源...${NC}"
    mkdir -p /etc/docker
    cat > /etc/docker/daemon.json <<EOF
{
  "registry-mirrors": ["https://registry.cn-hangzhou.aliyuncs.com"]
}
EOF
    systemctl daemon-reexec || true
    systemctl restart docker || true
}

# 显示菜单
show_menu() {
    echo -e "\n${YELLOW}请选择操作:${NC}"
    echo "1) 安装/升级 Docker、Docker Compose、Watchtower"
    echo "2) 卸载 Docker、Docker Compose"
    echo "3) 安装 Portainer 管理面板"
    echo "0) 退出脚本"
    read -p "请输入数字选择: " choice
}

# 检查 Docker 是否已安装
check_docker_installed() {
    command -v docker &>/dev/null
}

# 检查 Docker Compose 是否已安装
check_docker_compose_installed() {
    command -v docker-compose &>/dev/null
}

# 安装 Docker
install_docker() {
    echo -e "\n${GREEN}正在安装 Docker...${NC}"
    case "$OS" in
        debian|ubuntu)
            apt update && apt install -y ca-certificates curl gnupg lsb-release
            install -m 0755 -d /etc/apt/keyrings
            curl -fsSL https://download.docker.com/linux/$OS/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            echo \
              "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$OS \
              $VERSION_CODENAME stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
            apt update && apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            ;;
        centos|rhel)
            yum install -y yum-utils
            yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            yum install -y docker-ce docker-ce-cli containerd.io
            ;;
        arch)
            pacman -Sy --noconfirm docker
            ;;
        *)
            echo -e "${RED}不支持的操作系统: $OS${NC}"
            exit 1
            ;;
    esac
    systemctl enable --now docker
    echo -e "${GREEN}Docker 安装完成！${NC}"
}

# 卸载 Docker
uninstall_docker() {
    echo -e "\n${RED}正在卸载 Docker...${NC}"
    case "$OS" in
        debian|ubuntu)
            apt purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            rm -rf /etc/apt/keyrings/docker.gpg
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

# 安装 Docker Compose（独立版本）
install_docker_compose() {
    echo -e "\n${GREEN}正在安装 Docker Compose...${NC}"
    LATEST_COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep '"tag_name"' | cut -d '"' -f 4)
    curl -L "https://github.com/docker/compose/releases/download/${LATEST_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    echo -e "${GREEN}Docker Compose 安装完成！${NC}"
}

# 卸载 Docker Compose
uninstall_docker_compose() {
    echo -e "\n${RED}正在卸载 Docker Compose...${NC}"
    rm -f /usr/local/bin/docker-compose
    echo -e "${GREEN}Docker Compose 已卸载！${NC}"
}

# 安装 Watchtower
install_watchtower() {
    echo -e "${GREEN}正在安装 Watchtower...${NC}"
    docker run -d \
      --name watchtower \
      --restart always \
      -v /var/run/docker.sock:/var/run/docker.sock \
      containrrr/watchtower \
      --cleanup \
      --interval 3600
    echo -e "${GREEN}Watchtower 已启动，每小时检查一次更新。${NC}"
}

# 安装 Portainer
install_portainer() {
    echo -e "${GREEN}正在安装 Portainer 管理面板...${NC}"
    docker volume create portainer_data
    docker run -d \
        -p 9000:9000 \
        -p 9443:9443 \
        --name portainer \
        --restart always \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -v portainer_data:/data \
        portainer/portainer-ce:latest
    echo -e "${GREEN}Portainer 安装完成！请访问 http://<你的IP>:9000 设置管理员账户并切换中文。${NC}"
}

# 主逻辑
if is_china_ip; then
    setup_cn_mirrors
fi

while true; do
    show_menu
    case $choice in
        1)
            check_docker_installed || install_docker
            check_docker_compose_installed || install_docker_compose
            install_watchtower
            ;;
        2)
            check_docker_installed && uninstall_docker || echo -e "${YELLOW}Docker 未安装，无需卸载${NC}"
            check_docker_compose_installed && uninstall_docker_compose || echo -e "${YELLOW}Docker Compose 未安装，无需卸载${NC}"
            ;;
        3)
            check_docker_installed || install_docker
            install_portainer
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

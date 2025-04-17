#!/bin/bash
set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color


# 系统检测
detect_system() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
        VERSION_ID=$VERSION_ID
        VERSION_CODENAME=${VERSION_CODENAME:-$(. /etc/os-release && echo "$VERSION_CODENAME")}
        echo -e "${GREEN}检测到系统: ${BLUE}$OS $VERSION_ID${NC}"
    else
        echo -e "${RED}无法检测操作系统类型，脚本退出。${NC}"
        exit 1
    fi
}

# 检测中国大陆IP
is_china_ip() {
    local country
    country=$(curl -s --max-time 5 https://ipapi.co/country_code/ || echo "XX")
    [[ "$country" == "CN" ]]
}

# 设置国内镜像源
setup_cn_mirrors() {
    echo -e "${YELLOW}检测到中国大陆IP，启用国内加速源...${NC}"
    
    # Docker镜像设置
    mkdir -p /etc/docker
    cat > /etc/docker/daemon.json <<EOF
{
  "registry-mirrors": ["https://registry.cn-hangzhou.aliyuncs.com"],
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2"
}
EOF

    # 系统包管理器镜像
    case "$OS" in
        debian|ubuntu)
            sudo sed -i 's|http://.*archive.ubuntu.com|https://mirrors.aliyun.com|g' /etc/apt/sources.list
            sudo sed -i 's|http://.*security.ubuntu.com|https://mirrors.aliyun.com|g' /etc/apt/sources.list
            ;;
        centos|rhel)
            sudo sed -i 's|^mirrorlist=|#mirrorlist=|g' /etc/yum.repos.d/*
            sudo sed -i 's|^#baseurl=http://mirror.centos.org|baseurl=https://mirrors.aliyun.com|g' /etc/yum.repos.d/*
            ;;
    esac
    
    systemctl daemon-reexec
    systemctl restart docker || true
}

# 主菜单
show_menu() {
    clear
    echo -e "\n${BLUE}==== Docker 管理脚本 ====${NC}"
    echo -e "${GREEN}1) 安装/更新 Docker & Docker Compose"
    echo -e "2) 卸载 Docker & Docker Compose"
    echo -e "3) 安装 Portainer (Web管理界面)"
    echo -e "4) 安装 Watchtower (自动更新容器)"
    echo -e "5) 系统清理"
    echo -e "0) 退出${NC}"
    read -p "请输入选择: " choice
}

# Docker安装
install_docker() {
    echo -e "\n${BLUE}=== 安装 Docker ===${NC}"
    
    case "$OS" in
        debian|ubuntu)
            sudo apt update && sudo apt install -y apt-transport-https ca-certificates curl gnupg lsb-release
            sudo install -m 0755 -d /etc/apt/keyrings
            curl -fsSL https://download.docker.com/linux/$OS/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$OS $VERSION_CODENAME stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
            sudo apt update && sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            ;;
        centos|rhel)
            sudo yum install -y yum-utils device-mapper-persistent-data lvm2
            sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            sudo yum install -y docker-ce docker-ce-cli containerd.io
            ;;
        arch)
            sudo pacman -Sy --noconfirm docker
            ;;
    esac
    
    sudo systemctl enable --now docker
    sudo usermod -aG docker $USER || true
    echo -e "${GREEN}Docker 安装成功!${NC}"
}

# Docker Compose安装
install_compose() {
    echo -e "\n${BLUE}=== 安装 Docker Compose ===${NC}"
    
    COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep '"tag_name"' | cut -d '"' -f 4)
    sudo curl -L "https://github.com/docker/compose/releases/download/$COMPOSE_VERSION/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
    
    echo -e "${GREEN}Docker Compose 安装成功!${NC}"
    docker-compose --version
}

# Portainer安装
install_portainer() {
    echo -e "\n${BLUE}=== 安装 Portainer ===${NC}"
    
    docker volume create portainer_data
    docker run -d \
        -p 8000:8000 \
        -p 9443:9443 \
        --name portainer \
        --restart always \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -v portainer_data:/data \
        portainer/portainer-ce:latest
    
    echo -e "${GREEN}Portainer 安装成功!${NC}"
    echo -e "访问地址: ${YELLOW}https://localhost:9443${NC}"
}

# Watchtower安装
install_watchtower() {
    echo -e "\n${BLUE}=== 安装 Watchtower ===${NC}"
    
    docker run -d \
        --name watchtower \
        --restart always \
        -v /var/run/docker.sock:/var/run/docker.sock \
        containrrr/watchtower \
        --cleanup \
        --schedule "0 0 4 * * *" \
        --label-enable
    
    echo -e "${GREEN}Watchtower 安装成功!${NC}"
    echo -e "将每天凌晨4点检查更新"
}

# 系统清理
system_cleanup() {
    echo -e "\n${BLUE}=== 系统清理 ===${NC}"
    
    docker system prune -af
    docker volume prune -f
    docker network prune -f
    
    case "$OS" in
        debian|ubuntu)
            sudo apt autoremove -y
            sudo apt clean
            ;;
        centos|rhel)
            sudo yum autoremove -y
            sudo yum clean all
            ;;
    esac
    
    echo -e "${GREEN}清理完成!${NC}"
}

# 卸载Docker
uninstall_docker() {
    echo -e "\n${RED}=== 卸载 Docker ===${NC}"
    
    case "$OS" in
        debian|ubuntu)
            sudo apt purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            sudo rm -rf /etc/apt/keyrings/docker.gpg
            sudo rm -rf /etc/apt/sources.list.d/docker.list
            ;;
        centos|rhel)
            sudo yum remove -y docker-ce docker-ce-cli containerd.io
            sudo rm -rf /etc/yum.repos.d/docker-ce.repo
            ;;
        arch)
            sudo pacman -R --noconfirm docker
            ;;
    esac
    
    sudo rm -f /usr/local/bin/docker-compose
    sudo rm -rf /var/lib/docker
    echo -e "${GREEN}Docker 已完全卸载!${NC}"
}

# 主执行流程
fix_locale
detect_system

if is_china_ip; then
    setup_cn_mirrors
fi

while true; do
    show_menu
    case $choice in
        1)
            install_docker
            install_compose
            ;;
        2)
            uninstall_docker
            ;;
        3)
            install_portainer
            ;;
        4)
            install_watchtower
            ;;
        5)
            system_cleanup
            ;;
        0)
            echo -e "${GREEN}退出脚本...${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}无效选择!${NC}"
            ;;
    esac
    
    read -p "按Enter键继续..."
done

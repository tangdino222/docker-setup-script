#!/bin/bash
set -e

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# System detection
detect_system() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
        VERSION_ID=$VERSION_ID
        VERSION_CODENAME=${VERSION_CODENAME:-$(. /etc/os-release && echo "$VERSION_CODENAME")}
        echo -e "${GREEN}Detected system: ${BLUE}$OS $VERSION_ID${NC}"
    else
        echo -e "${RED}Cannot detect OS type. Exiting.${NC}"
        exit 1
    fi
}

# Check China IP
is_china_ip() {
    local country
    country=$(curl -s --max-time 5 https://ipapi.co/country_code/ || echo "XX")
    [[ "$country" == "CN" ]]
}

# Setup China mirrors
setup_cn_mirrors() {
    echo -e "${YELLOW}Using China mainland IP, setting up mirrors...${NC}"
    
    # Docker mirror
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

    # APT/YUM mirrors for China
    case "$OS" in
        debian|ubuntu)
            sed -i 's|http://.*archive.ubuntu.com|https://mirrors.aliyun.com|g' /etc/apt/sources.list
            sed -i 's|http://.*security.ubuntu.com|https://mirrors.aliyun.com|g' /etc/apt/sources.list
            ;;
        centos|rhel)
            sed -i 's|^mirrorlist=|#mirrorlist=|g' /etc/yum.repos.d/*
            sed -i 's|^#baseurl=http://mirror.centos.org|baseurl=https://mirrors.aliyun.com|g' /etc/yum.repos.d/*
            ;;
    esac
    
    systemctl daemon-reexec
    systemctl restart docker || true
}

# Main menu
show_menu() {
    clear
    echo -e "\n${BLUE}==== Docker Management Script ====${NC}"
    echo -e "${GREEN}1) Install/Update Docker & Docker Compose"
    echo -e "2) Uninstall Docker & Docker Compose"
    echo -e "3) Install Portainer (Web UI)"
    echo -e "4) Install Watchtower (Auto-updater)"
    echo -e "5) System Cleanup"
    echo -e "0) Exit${NC}"
    read -p "Enter your choice: " choice
}

# Docker installation
install_docker() {
    echo -e "\n${BLUE}=== Installing Docker ===${NC}"
    
    case "$OS" in
        debian|ubuntu)
            apt update && apt install -y apt-transport-https ca-certificates curl gnupg lsb-release
            install -m 0755 -d /etc/apt/keyrings
            curl -fsSL https://download.docker.com/linux/$OS/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$OS $VERSION_CODENAME stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
            apt update && apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            ;;
        centos|rhel)
            yum install -y yum-utils device-mapper-persistent-data lvm2
            yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            yum install -y docker-ce docker-ce-cli containerd.io
            ;;
        arch)
            pacman -Sy --noconfirm docker
            ;;
    esac
    
    systemctl enable --now docker
    usermod -aG docker $USER || true
    echo -e "${GREEN}Docker installed successfully!${NC}"
}

# Docker Compose installation
install_compose() {
    echo -e "\n${BLUE}=== Installing Docker Compose ===${NC}"
    
    COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep '"tag_name"' | cut -d '"' -f 4)
    curl -L "https://github.com/docker/compose/releases/download/$COMPOSE_VERSION/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    
    echo -e "${GREEN}Docker Compose installed successfully!${NC}"
    docker-compose --version
}

# Portainer installation
install_portainer() {
    echo -e "\n${BLUE}=== Installing Portainer ===${NC}"
    
    docker volume create portainer_data
    docker run -d \
        -p 8000:8000 \
        -p 9443:9443 \
        --name portainer \
        --restart always \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -v portainer_data:/data \
        portainer/portainer-ce:latest
    
    echo -e "${GREEN}Portainer installed successfully!${NC}"
    echo -e "Access at: ${YELLOW}https://localhost:9443${NC}"
}

# Watchtower installation
install_watchtower() {
    echo -e "\n${BLUE}=== Installing Watchtower ===${NC}"
    
    docker run -d \
        --name watchtower \
        --restart always \
        -v /var/run/docker.sock:/var/run/docker.sock \
        containrrr/watchtower \
        --cleanup \
        --schedule "0 0 4 * * *" \
        --label-enable
    
    echo -e "${GREEN}Watchtower installed successfully!${NC}"
    echo -e "Will check for updates daily at 4 AM"
}

# Cleanup function
system_cleanup() {
    echo -e "\n${BLUE}=== System Cleanup ===${NC}"
    
    docker system prune -af
    docker volume prune -f
    docker network prune -f
    
    case "$OS" in
        debian|ubuntu)
            apt autoremove -y
            apt clean
            ;;
        centos|rhel)
            yum autoremove -y
            yum clean all
            ;;
    esac
    
    echo -e "${GREEN}Cleanup completed!${NC}"
}

# Uninstall function
uninstall_docker() {
    echo -e "\n${RED}=== Uninstalling Docker ===${NC}"
    
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
    
    rm -f /usr/local/bin/docker-compose
    rm -rf /var/lib/docker
    echo -e "${GREEN}Docker has been completely removed!${NC}"
}

# Main execution
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
            echo -e "${GREEN}Exiting...${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid choice!${NC}"
            ;;
    esac
    
    read -p "Press Enter to continue..."
done

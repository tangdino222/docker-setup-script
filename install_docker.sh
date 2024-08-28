#!/bin/bash

# 更新 APT 包索引
apt update

# 移除旧版本的 Docker 和 Docker Compose（如果有）
apt remove docker docker-engine docker.io containerd runc docker-compose -y

# 安装必要的依赖项
apt install apt-transport-https ca-certificates curl gnupg lsb-release -y

# 如果文件存在，则删除它
[ -f /usr/share/keyrings/docker-archive-keyring.gpg ] && sudo rm /usr/share/keyrings/docker-archive-keyring.gpg

# 添加 Docker 官方 GPG 密钥
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

# 设置 Docker 仓库
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

# 更新 APT 包索引
apt update

# 安装最新版 Docker
apt install docker-ce docker-ce-cli containerd.io -y

# 下载最新版本的 Docker Compose
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose

# 赋予执行权限
chmod +x /usr/local/bin/docker-compose

# 创建软链接（如果需要）
ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose

# 启动并启用 Docker 服务
systemctl start docker
systemctl enable docker

# 显示安装的版本
docker --version
docker-compose --version

echo "Docker 和 Docker Compose 已成功安装！"

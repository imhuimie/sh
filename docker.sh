#!/bin/bash

# 定义颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 检查 root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}请使用 root 权限运行 (sudo).${NC}"
  exit 1
fi

echo -e "${BLUE}=================================================${NC}"
echo -e "${BLUE}    Docker 一键安装脚本 V2 (国内直连优化版)      ${NC}"
echo -e "${BLUE}=================================================${NC}"

# 1. 路径配置
echo -e "\n${YELLOW}配置 Docker 数据存储路径...${NC}"
DOCKER_DATA_ROOT="/var/lib/docker"
read -p "是否自定义数据路径 (默认 /var/lib/docker)? [y/N]: " custom_path
if [[ "$custom_path" =~ ^[Yy]$ ]]; then
    read -p "请输入绝对路径 (例如 /data/docker): " input_path
    if [[ "$input_path" == /* ]]; then
        DOCKER_DATA_ROOT="$input_path"
        mkdir -p "$DOCKER_DATA_ROOT"
        echo -e "${GREEN}-> 将安装至: $DOCKER_DATA_ROOT${NC}"
    else
        echo -e "${RED}路径无效，使用默认路径。${NC}"
    fi
fi

# 2. 手动配置阿里云源并安装 (绕过 get.docker.com)
echo -e "\n${BLUE}正在识别系统并配置阿里云源...${NC}"

install_success=false

# 检测系统发行版
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
else
    echo -e "${RED}无法检测系统版本，脚本退出。${NC}"
    exit 1
fi

if [[ "$OS" == "ubuntu" || "$OS" == "debian" || "$OS" == "kali" ]]; then
    echo -e "${GREEN}检测到 Debian/Ubuntu 系系统...${NC}"
    
    # 更新索引并安装依赖
    apt-get update
    apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release

    # 添加阿里云 GPG Key
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://mirrors.aliyun.com/docker-ce/linux/${OS}/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg --yes

    # 写入软件源
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://mirrors.aliyun.com/docker-ce/linux/${OS} \
      $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # 安装 Docker
    apt-get update
    echo -e "${BLUE}开始通过阿里云镜像下载 Docker...${NC}"
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    
    if [ $? -eq 0 ]; then install_success=true; fi

elif [[ "$OS" == "centos" || "$OS" == "rhel" || "$OS" == "fedora" || "$OS" == "rocky" || "$OS" == "almalinux" ]]; then
    echo -e "${GREEN}检测到 CentOS/RHEL 系系统...${NC}"
    
    # 安装工具
    yum install -y yum-utils
    
    # 添加阿里云 repo
    echo -e "${BLUE}添加阿里云 Docker Yum 源...${NC}"
    yum-config-manager --add-repo https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
    
    # 替换 repo 中的下载地址为阿里云 (某些版本需要)
    sed -i 's+download.docker.com+mirrors.aliyun.com/docker-ce+' /etc/yum.repos.d/docker-ce.repo

    # 安装
    yum install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    
    if [ $? -eq 0 ]; then install_success=true; fi
else
    echo -e "${RED}不支持的操作系统: $OS${NC}"
    echo "建议手动安装。"
    exit 1
fi

if [ "$install_success" = false ]; then
    echo -e "${RED}Docker 安装失败！请检查上方报错信息 (通常是网络源问题)。${NC}"
    exit 1
fi

echo -e "${GREEN}Docker 软件安装成功!${NC}"

# 3. 配置 daemon.json (路径 + 镜像加速)
echo -e "\n${BLUE}配置镜像加速与存储路径...${NC}"
mkdir -p /etc/docker

# 针对国内环境的加强版配置，优先使用 docker.1ms.run
cat > /etc/docker/daemon.json <<EOF
{
  "data-root": "$DOCKER_DATA_ROOT",
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m",
    "max-file": "3"
  },
  "registry-mirrors": [
    "https://docker.1ms.run",
    "https://docker.m.daocloud.io",
    "https://huecker.io",
    "https://dockerhub.timeweb.cloud",
    "https://noohub.ru"
  ]
}
EOF

# 4. 启动服务
echo -e "\n${BLUE}启动 Docker 服务...${NC}"
systemctl daemon-reload
systemctl enable docker
systemctl restart docker

# 5. 验证
echo -e "\n${BLUE}================ 验证状态 ================${NC}"
if command -v docker &> /dev/null; then
    docker --version
    docker compose version
    
    REAL_DIR=$(docker info -f '{{.DockerRootDir}}')
    echo -e "数据目录: ${GREEN}${REAL_DIR}${NC}"
    
    # 检查镜像加速是否生效
    echo -e "镜像源列表:"
    docker info | grep -A 5 "Registry Mirrors"
    
    if [[ "$REAL_DIR" == "$DOCKER_DATA_ROOT" ]]; then
        echo -e "${GREEN}Docker 已安装并成功配置到指定目录！${NC}"
    else
        echo -e "${RED}注意：数据目录似乎未生效，请检查 /etc/docker/daemon.json 格式${NC}"
    fi
else
    echo -e "${RED}验证失败：找不到 docker 命令。${NC}"
fi

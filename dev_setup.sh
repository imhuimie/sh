#!/bin/bash

# 开发环境安装脚本
# 此脚本帮助开发者在全新的 Linux 系统中选择性安装常用开发工具和基础软件包

set -e  # 遇到错误立即退出
set -u  # 使用未定义的变量时报错

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # 无颜色

# 打印带颜色的信息
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查是否为 root 用户
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        print_error "请使用 root 权限运行此脚本"
        exit 1
    fi
}

# 检测 Linux 发行版
detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO=$ID
        VERSION=$VERSION_ID
        print_info "检测到 Linux 发行版: $DISTRO $VERSION"
    else
        print_error "无法检测 Linux 发行版"
        exit 1
    fi
}

# 安装必要基础工具
install_base_tools() {
    print_info "安装必要基础工具..."
    
    case $DISTRO in
        ubuntu|debian)
            apt update
            apt install -y curl wget
            ;;
        centos|rhel|fedora)
            if command -v dnf &> /dev/null; then
                dnf install -y curl wget
            else
                yum install -y curl wget
            fi
            ;;
        *)
            print_error "不支持的 Linux 发行版: $DISTRO"
            exit 1
            ;;
    esac
    
    print_success "必要基础工具安装完成"
    
    # 安装可选基础工具
    install_optional_tools
}

# 安装可选基础工具
install_optional_tools() {
    echo "=========================================="
    echo "请选择要安装的可选基础工具（输入对应的数字，多个选项用空格分隔）："
    echo "1) 编辑器工具 (vim, nano)"
    echo "2) 系统监控工具 (htop, net-tools)"
    echo "3) 压缩工具 (zip, unzip, tar)"
    echo "4) SSH 服务器"
    echo "5) 开发构建工具 (build-essential/Development Tools)"
    echo "0) 全部安装"
    echo "c) 取消安装"
    echo "=========================================="
    
    read -p "请输入您的选择: " tool_choices
    
    if [[ "$tool_choices" == "c" ]]; then
        print_info "取消安装可选基础工具"
        return
    fi
    
    INSTALL_EDITORS=false
    INSTALL_MONITORING=false
    INSTALL_COMPRESSION=false
    INSTALL_SSH=false
    INSTALL_BUILD_TOOLS=false
    
    if [[ "$tool_choices" == "0" ]]; then
        INSTALL_EDITORS=true
        INSTALL_MONITORING=true
        INSTALL_COMPRESSION=true
        INSTALL_SSH=true
        INSTALL_BUILD_TOOLS=true
    else
        for choice in $tool_choices; do
            case $choice in
                1) INSTALL_EDITORS=true ;;
                2) INSTALL_MONITORING=true ;;
                3) INSTALL_COMPRESSION=true ;;
                4) INSTALL_SSH=true ;;
                5) INSTALL_BUILD_TOOLS=true ;;
                *) print_warning "忽略无效的选项: $choice" ;;
            esac
        done
    fi
    
    case $DISTRO in
        ubuntu|debian)
            # 编辑器工具
            if $INSTALL_EDITORS; then
                print_info "安装编辑器工具..."
                apt install -y vim nano
            fi
            
            # 系统监控工具
            if $INSTALL_MONITORING; then
                print_info "安装系统监控工具..."
                apt install -y htop net-tools
            fi
            
            # 压缩工具
            if $INSTALL_COMPRESSION; then
                print_info "安装压缩工具..."
                apt install -y zip unzip tar
            fi
            
            # SSH 服务器
            if $INSTALL_SSH; then
                print_info "安装 SSH 服务器..."
                apt install -y openssh-server
            fi
            
            # 开发构建工具
            if $INSTALL_BUILD_TOOLS; then
                print_info "安装开发构建工具..."
                apt install -y build-essential
            fi
            ;;
            
        centos|rhel|fedora)
            # 编辑器工具
            if $INSTALL_EDITORS; then
                print_info "安装编辑器工具..."
                if command -v dnf &> /dev/null; then
                    dnf install -y vim nano
                else
                    yum install -y vim nano
                fi
            fi
            
            # 系统监控工具
            if $INSTALL_MONITORING; then
                print_info "安装系统监控工具..."
                if command -v dnf &> /dev/null; then
                    dnf install -y htop net-tools
                else
                    yum install -y htop net-tools
                fi
            fi
            
            # 压缩工具
            if $INSTALL_COMPRESSION; then
                print_info "安装压缩工具..."
                if command -v dnf &> /dev/null; then
                    dnf install -y zip unzip tar
                else
                    yum install -y zip unzip tar
                fi
            fi
            
            # SSH 服务器
            if $INSTALL_SSH; then
                print_info "安装 SSH 服务器..."
                if command -v dnf &> /dev/null; then
                    dnf install -y openssh-server
                else
                    yum install -y openssh-server
                fi
            fi
            
            # 开发构建工具
            if $INSTALL_BUILD_TOOLS; then
                print_info "安装开发构建工具..."
                if command -v dnf &> /dev/null; then
                    dnf groupinstall -y "Development Tools"
                else
                    yum groupinstall -y "Development Tools"
                fi
            fi
            ;;
    esac
    
    print_success "可选基础工具安装完成"
}

# 安装 Git
install_git() {
    print_info "安装 Git..."
    
    case $DISTRO in
        ubuntu|debian)
            apt install -y git
            ;;
        centos|rhel|fedora)
            if command -v dnf &> /dev/null; then
                dnf install -y git
            else
                yum install -y git
            fi
            ;;
    esac
    
    print_success "Git 安装完成: $(git --version)"
}

# 安装 C/C++ 开发环境
install_cpp() {
    print_info "安装 C/C++ 开发环境..."
    
    case $DISTRO in
        ubuntu|debian)
            apt install -y build-essential gdb cmake
            ;;
        centos|rhel|fedora)
            if command -v dnf &> /dev/null; then
                dnf groupinstall -y "Development Tools"
                dnf install -y gdb cmake
            else
                yum groupinstall -y "Development Tools"
                yum install -y gdb cmake
            fi
            ;;
    esac
    
    print_success "C/C++ 开发环境安装完成: $(gcc --version | head -n 1)"
}

# 安装 Python3
install_python() {
    # 显示 Python 版本选项
    echo "可用的 Python 版本："
    echo "1) Python 3.8 (推荐的稳定版本)"
    echo "2) Python 3.9"
    echo "3) Python 3.10"
    echo "4) Python 3.11"
    echo "5) Python 3.12"
    echo "6) 系统默认版本"
    echo "7) 自定义版本"
    read -p "请选择要安装的 Python 版本 [1-7]: " python_choice
    
    case $python_choice in
        1)
            PYTHON_VERSION="3.8"
            ;;
        2)
            PYTHON_VERSION="3.9"
            ;;
        3)
            PYTHON_VERSION="3.10"
            ;;
        4)
            PYTHON_VERSION="3.11"
            ;;
        5)
            PYTHON_VERSION="3.12"
            ;;
        6)
            PYTHON_VERSION="default"
            ;;
        7)
            read -p "请输入要安装的 Python 版本 (例如 3.7.9): " PYTHON_VERSION
            ;;
        *)
            print_warning "无效选择，使用系统默认版本"
            PYTHON_VERSION="default"
            ;;
    esac
    
    print_info "安装 Python $PYTHON_VERSION 开发环境..."
    
    case $DISTRO in
        ubuntu|debian)
            if [ "$PYTHON_VERSION" == "default" ]; then
                apt install -y python3 python3-pip python3-venv python3-dev
            else
                # 添加 deadsnakes PPA 以获取特定版本的 Python
                apt install -y software-properties-common
                add-apt-repository -y ppa:deadsnakes/ppa
                apt update
                
                # 提取主版本号 (例如 3.8.10 -> 3.8)
                PYTHON_MAJOR_VERSION=$(echo $PYTHON_VERSION | grep -oE '^[0-9]+\.[0-9]+')
                
                apt install -y python${PYTHON_MAJOR_VERSION} python${PYTHON_MAJOR_VERSION}-venv python${PYTHON_MAJOR_VERSION}-dev
                apt install -y python3-pip
                
                # 创建符号链接
                update-alternatives --install /usr/bin/python3 python3 /usr/bin/python${PYTHON_MAJOR_VERSION} 1
                update-alternatives --set python3 /usr/bin/python${PYTHON_MAJOR_VERSION}
            fi
            ;;
        centos|rhel|fedora)
            if command -v dnf &> /dev/null; then
                if [ "$PYTHON_VERSION" == "default" ]; then
                    dnf install -y python3 python3-pip python3-devel
                else
                    # 提取主版本号
                    PYTHON_MAJOR_VERSION=$(echo $PYTHON_VERSION | grep -oE '^[0-9]+\.[0-9]+')
                    PYTHON_NO_DOT=${PYTHON_MAJOR_VERSION/./}
                    
                    # 使用 SCL 安装特定版本的 Python
                    dnf install -y centos-release-scl
                    dnf install -y rh-python${PYTHON_NO_DOT} rh-python${PYTHON_NO_DOT}-python-devel
                    
                    # 创建符号链接
                    ln -sf /opt/rh/rh-python${PYTHON_NO_DOT}/root/usr/bin/python3 /usr/bin/python3
                    ln -sf /opt/rh/rh-python${PYTHON_NO_DOT}/root/usr/bin/pip3 /usr/bin/pip3
                fi
            else
                yum install -y python3 python3-pip python3-devel
            fi
            ;;
    esac
    
    # 安装 pipenv 和 virtualenv
    pip3 install --upgrade pip
    pip3 install pipenv virtualenv
    
    print_success "Python 开发环境安装完成: $(python3 --version)"
}

# 安装 Go (Golang)
install_golang() {
    # 显示 Go 版本选项
    echo "可用的 Go 版本："
    echo "1) Go 1.20 (推荐的稳定版本)"
    echo "2) Go 1.21"
    echo "3) Go 1.19"
    echo "4) Go 1.18"
    echo "5) 自定义版本"
    read -p "请选择要安装的 Go 版本 [1-5]: " go_choice
    
    case $go_choice in
        1)
            GO_VERSION="1.20.11"
            ;;
        2)
            GO_VERSION="1.21.4"
            ;;
        3)
            GO_VERSION="1.19.13"
            ;;
        4)
            GO_VERSION="1.18.10"
            ;;
        5)
            read -p "请输入要安装的 Go 版本 (例如 1.17.8): " GO_VERSION
            ;;
        *)
            print_warning "无效选择，使用推荐的稳定版本 1.20.11"
            GO_VERSION="1.20.11"
            ;;
    esac
    
    print_info "安装 Go $GO_VERSION..."
    
    # 下载并安装指定版本的 Go
    wget -q https://golang.org/dl/go${GO_VERSION}.linux-amd64.tar.gz
    
    # 检查下载是否成功
    if [ $? -ne 0 ]; then
        print_error "下载 Go ${GO_VERSION} 失败，请检查版本号是否正确"
        return 1
    fi
    
    tar -C /usr/local -xzf go${GO_VERSION}.linux-amd64.tar.gz
    rm go${GO_VERSION}.linux-amd64.tar.gz
    
    # 设置环境变量
    echo 'export PATH=$PATH:/usr/local/go/bin' > /etc/profile.d/go.sh
    echo 'export GOPATH=$HOME/go' >> /etc/profile.d/go.sh
    echo 'export PATH=$PATH:$GOPATH/bin' >> /etc/profile.d/go.sh
    chmod +x /etc/profile.d/go.sh
    
    # 立即生效
    source /etc/profile.d/go.sh
    
    print_success "Go 安装完成: $(/usr/local/go/bin/go version)"
}

# 安装 Java
install_java() {
    # 显示 Java 版本选项
    echo "可用的 Java 版本："
    echo "1) OpenJDK 11 (推荐的长期支持版本)"
    echo "2) OpenJDK 17 (推荐的长期支持版本)"
    echo "3) OpenJDK 8"
    echo "4) OpenJDK 21 (最新长期支持版本)"
    echo "5) 自定义版本"
    read -p "请选择要安装的 Java 版本 [1-5]: " java_choice
    
    case $java_choice in
        1)
            JAVA_VERSION="11"
            ;;
        2)
            JAVA_VERSION="17"
            ;;
        3)
            JAVA_VERSION="8"
            ;;
        4)
            JAVA_VERSION="21"
            ;;
        5)
            read -p "请输入要安装的 Java 版本 (例如 15): " JAVA_VERSION
            ;;
        *)
            print_warning "无效选择，使用推荐的稳定版本 OpenJDK 11"
            JAVA_VERSION="11"
            ;;
    esac
    
    print_info "安装 OpenJDK $JAVA_VERSION..."
    
    case $DISTRO in
        ubuntu|debian)
            # 检查版本是否可用
            if apt-cache search openjdk-${JAVA_VERSION}-jdk | grep -q openjdk-${JAVA_VERSION}-jdk; then
                apt install -y openjdk-${JAVA_VERSION}-jdk
            else
                print_error "OpenJDK ${JAVA_VERSION} 在当前系统上不可用"
                return 1
            fi
            ;;
        centos|rhel|fedora)
            if command -v dnf &> /dev/null; then
                # 检查版本是否可用
                if dnf list java-${JAVA_VERSION}-openjdk-devel &>/dev/null; then
                    dnf install -y java-${JAVA_VERSION}-openjdk-devel
                else
                    print_error "OpenJDK ${JAVA_VERSION} 在当前系统上不可用"
                    return 1
                fi
            else
                # 检查版本是否可用
                if yum list java-${JAVA_VERSION}-openjdk-devel &>/dev/null; then
                    yum install -y java-${JAVA_VERSION}-openjdk-devel
                else
                    print_error "OpenJDK ${JAVA_VERSION} 在当前系统上不可用"
                    return 1
                fi
            fi
            ;;
    esac
    
    # 设置 JAVA_HOME
    if [ -d "/usr/lib/jvm/java-${JAVA_VERSION}-openjdk-amd64" ]; then
        echo "export JAVA_HOME=/usr/lib/jvm/java-${JAVA_VERSION}-openjdk-amd64" > /etc/profile.d/java.sh
    elif [ -d "/usr/lib/jvm/java-${JAVA_VERSION}-openjdk" ]; then
        echo "export JAVA_HOME=/usr/lib/jvm/java-${JAVA_VERSION}-openjdk" > /etc/profile.d/java.sh
    elif [ -d "/usr/lib/jvm/java-${JAVA_VERSION}" ]; then
        echo "export JAVA_HOME=/usr/lib/jvm/java-${JAVA_VERSION}" > /etc/profile.d/java.sh
    fi
    
    if [ -f "/etc/profile.d/java.sh" ]; then
        echo 'export PATH=$PATH:$JAVA_HOME/bin' >> /etc/profile.d/java.sh
        chmod +x /etc/profile.d/java.sh
        source /etc/profile.d/java.sh
    fi
    
    print_success "Java 开发环境安装完成: $(java -version 2>&1 | head -n 1)"
}

# 安装 Node.js 和 NVM
install_nodejs() {
    print_info "安装 NVM (Node Version Manager)..."
    
    # 安装 NVM
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.5/install.sh | bash
    
    # 设置 NVM 环境变量
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    
    # 显示 Node.js 版本选项
    echo "可用的 Node.js 版本："
    echo "1) Node.js 18 LTS (推荐的稳定版本)"
    echo "2) Node.js 20 LTS (最新长期支持版本)"
    echo "3) Node.js 16 LTS"
    echo "4) Node.js 最新版"
    echo "5) 自定义版本"
    read -p "请选择要安装的 Node.js 版本 [1-5]: " node_choice
    
    case $node_choice in
        1)
            NODE_VERSION="18"
            ;;
        2)
            NODE_VERSION="20"
            ;;
        3)
            NODE_VERSION="16"
            ;;
        4)
            NODE_VERSION="node"  # 最新版
            ;;
        5)
            read -p "请输入要安装的 Node.js 版本 (例如 14.17.0): " NODE_VERSION
            ;;
        *)
            print_warning "无效选择，使用推荐的稳定版本 Node.js 18 LTS"
            NODE_VERSION="18"
            ;;
    esac
    
    print_info "安装 Node.js $NODE_VERSION..."
    
    # 安装指定版本的 Node.js
    if [ "$NODE_VERSION" == "node" ]; then
        nvm install node
    else
        nvm install $NODE_VERSION
    fi
    
    # 检查安装是否成功
    if [ $? -ne 0 ]; then
        print_error "安装 Node.js ${NODE_VERSION} 失败，请检查版本号是否正确"
        return 1
    fi
    
    # 设置默认版本
    if [ "$NODE_VERSION" == "node" ]; then
        nvm alias default node
    else
        nvm alias default $NODE_VERSION
    fi
    
    # 安装常用的全局包
    npm install -g npm@latest yarn
    
    print_success "Node.js 和 NVM 安装完成: $(node -v)"
}

# 安装 Rust
install_rust() {
    # 显示 Rust 版本选项
    echo "可用的 Rust 安装通道："
    echo "1) stable (推荐的稳定版本)"
    echo "2) beta"
    echo "3) nightly"
    echo "4) 特定版本"
    read -p "请选择要安装的 Rust 通道或版本 [1-4]: " rust_choice
    
    case $rust_choice in
        1)
            RUST_CHANNEL="stable"
            ;;
        2)
            RUST_CHANNEL="beta"
            ;;
        3)
            RUST_CHANNEL="nightly"
            ;;
        4)
            read -p "请输入要安装的 Rust 版本 (例如 1.68.0): " RUST_VERSION
            RUST_CHANNEL="--version $RUST_VERSION"
            ;;
        *)
            print_warning "无效选择，使用推荐的稳定版本 stable"
            RUST_CHANNEL="stable"
            ;;
    esac
    
    print_info "安装 Rust $RUST_CHANNEL..."
    
    # 安装 Rust
    if [[ "$RUST_CHANNEL" == "--version"* ]]; then
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y $RUST_CHANNEL
    else
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain $RUST_CHANNEL
    fi
    
    # 设置环境变量
    source $HOME/.cargo/env
    
    print_success "Rust 安装完成: $(rustc --version)"
}

# 安装 Ruby
install_ruby() {
    # 显示 Ruby 版本选项
    echo "可用的 Ruby 版本："
    echo "1) 系统默认版本"
    echo "2) 使用 RVM 安装 Ruby 3.0 (推荐的稳定版本)"
    echo "3) 使用 RVM 安装 Ruby 3.1"
    echo "4) 使用 RVM 安装 Ruby 3.2"
    echo "5) 使用 RVM 安装自定义版本"
    read -p "请选择要安装的 Ruby 版本 [1-5]: " ruby_choice
    
    case $ruby_choice in
        1)
            RUBY_VERSION="system"
            ;;
        2)
            RUBY_VERSION="3.0"
            ;;
        3)
            RUBY_VERSION="3.1"
            ;;
        4)
            RUBY_VERSION="3.2"
            ;;
        5)
            read -p "请输入要安装的 Ruby 版本 (例如 2.7.6): " RUBY_VERSION
            ;;
        *)
            print_warning "无效选择，使用系统默认版本"
            RUBY_VERSION="system"
            ;;
    esac
    
    if [ "$RUBY_VERSION" == "system" ]; then
        print_info "安装系统默认 Ruby 版本..."
        
        case $DISTRO in
            ubuntu|debian)
                apt install -y ruby-full
                ;;
            centos|rhel|fedora)
                if command -v dnf &> /dev/null; then
                    dnf install -y ruby ruby-devel
                else
                    yum install -y ruby ruby-devel
                fi
                ;;
        esac
    else
        print_info "安装 RVM 和 Ruby $RUBY_VERSION..."
        
        # 安装 RVM 依赖
        case $DISTRO in
            ubuntu|debian)
                apt install -y gnupg2 curl
                ;;
            centos|rhel|fedora)
                if command -v dnf &> /dev/null; then
                    dnf install -y gnupg2 curl
                else
                    yum install -y gnupg2 curl
                fi
                ;;
        esac
        
        # 安装 RVM
        curl -sSL https://rvm.io/mpapis.asc | gpg2 --import -
        curl -sSL https://rvm.io/pkuczynski.asc | gpg2 --import -
        curl -sSL https://get.rvm.io | bash -s stable
        
        # 加载 RVM
        source /etc/profile.d/rvm.sh
        
        # 安装指定版本的 Ruby
        rvm install $RUBY_VERSION
        
        # 检查安装是否成功
        if [ $? -ne 0 ]; then
            print_error "安装 Ruby ${RUBY_VERSION} 失败，请检查版本号是否正确"
            return 1
        fi
        
        rvm use $RUBY_VERSION --default
    fi
    
    # 安装 Bundler
    gem install bundler
    
    print_success "Ruby 安装完成: $(ruby --version)"
}

# 安装 Docker CE
install_docker() {
    print_info "安装 Docker CE..."
    
    case $DISTRO in
        ubuntu|debian)
            # 安装依赖
            apt install -y apt-transport-https ca-certificates curl gnupg lsb-release
            
            # 添加 Docker 官方 GPG 密钥
            install -m 0755 -d /etc/apt/keyrings
            curl -fsSL https://download.docker.com/linux/$DISTRO/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            chmod a+r /etc/apt/keyrings/docker.gpg
            
            # 设置 Docker 仓库
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$DISTRO $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
            
            # 更新包索引
            apt update -y
            
            # 安装 Docker CE
            apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            ;;
        centos|rhel)
            # 安装依赖
            if command -v dnf &> /dev/null; then
                dnf install -y yum-utils
                # 添加 Docker 仓库
                dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
                # 安装 Docker CE
                dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            else
                yum install -y yum-utils
                # 添加 Docker 仓库
                yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
                # 安装 Docker CE
                yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            fi
            ;;
        fedora)
            # 安装依赖
            dnf install -y dnf-plugins-core
            # 添加 Docker 仓库
            dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
            # 安装 Docker CE
            dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            ;;
    esac
    
    # 启动 Docker 服务
    systemctl enable docker
    systemctl start docker
    
    # 添加当前用户到 docker 组
    if [ -n "$SUDO_USER" ]; then
        usermod -aG docker $SUDO_USER
    else
        print_warning "无法确定当前用户，请手动将用户添加到 docker 组"
    fi
    
    print_success "Docker CE 安装完成: $(docker --version)"
}

# 显示菜单并获取用户选择
show_menu() {
    clear
    echo "=========================================="
    echo "      Linux 开发环境安装脚本"
    echo "=========================================="
    echo "请选择要安装的开发工具（输入对应的数字，多个选项用空格分隔）："
    echo "1) 必要基础工具（curl, wget）"
    echo "2) 可选基础工具（vim, htop, zip 等）"
    echo "3) Git"
    echo "4) C/C++ 开发环境"
    echo "5) Python3 开发环境"
    echo "6) Go (Golang)"
    echo "7) Java 开发环境"
    echo "8) Node.js 和 NVM"
    echo "9) Rust"
        echo "10) Ruby"
    echo "11) Docker CE"
    echo "0) 全部安装"
    echo "q) 退出"
    echo "=========================================="
    
    read -p "请输入您的选择: " choices
    
    if [[ "$choices" == "q" ]]; then
        echo "退出安装程序"
        exit 0
    fi
    
    if [[ "$choices" == "0" ]]; then
        INSTALL_BASE=true
        INSTALL_OPTIONAL=true
        INSTALL_GIT=true
        INSTALL_CPP=true
        INSTALL_PYTHON=true
        INSTALL_GOLANG=true
        INSTALL_JAVA=true
        INSTALL_NODEJS=true
        INSTALL_RUST=true
        INSTALL_RUBY=true
        INSTALL_DOCKER=true
    else
        INSTALL_BASE=false
        INSTALL_OPTIONAL=false
        INSTALL_GIT=false
        INSTALL_CPP=false
        INSTALL_PYTHON=false
        INSTALL_GOLANG=false
        INSTALL_JAVA=false
        INSTALL_NODEJS=false
        INSTALL_RUST=false
        INSTALL_RUBY=false
        INSTALL_DOCKER=false
        
        for choice in $choices; do
            case $choice in
                1) INSTALL_BASE=true ;;
                2) INSTALL_OPTIONAL=true ;;
                3) INSTALL_GIT=true ;;
                4) INSTALL_CPP=true ;;
                5) INSTALL_PYTHON=true ;;
                6) INSTALL_GOLANG=true ;;
                7) INSTALL_JAVA=true ;;
                8) INSTALL_NODEJS=true ;;
                9) INSTALL_RUST=true ;;
                10) INSTALL_RUBY=true ;;
                11) INSTALL_DOCKER=true ;;
                *) print_warning "忽略无效的选项: $choice" ;;
            esac
        done
    fi
}

# 确认安装选项
confirm_installation() {
    echo "=========================================="
    echo "您选择安装以下工具："
    
    $INSTALL_BASE && echo "- 必要基础工具"
    $INSTALL_OPTIONAL && echo "- 可选基础工具"
    $INSTALL_GIT && echo "- Git"
    $INSTALL_CPP && echo "- C/C++ 开发环境"
    $INSTALL_PYTHON && echo "- Python3 开发环境"
    $INSTALL_GOLANG && echo "- Go (Golang)"
    $INSTALL_JAVA && echo "- Java 开发环境"
    $INSTALL_NODEJS && echo "- Node.js 和 NVM"
    $INSTALL_RUST && echo "- Rust"
    $INSTALL_RUBY && echo "- Ruby"
    $INSTALL_DOCKER && echo "- Docker CE"
    
    echo "=========================================="
    read -p "确认安装以上工具？(y/n): " confirm
    
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        print_info "取消安装"
        exit 0
    fi
}

# 主函数
main() {
    print_info "开始安装开发环境..."
    
    check_root
    detect_distro
    show_menu
    confirm_installation
    
    $INSTALL_BASE && install_base_tools
    $INSTALL_GIT && install_git
    $INSTALL_CPP && install_cpp
    $INSTALL_PYTHON && install_python
    $INSTALL_GOLANG && install_golang
    $INSTALL_JAVA && install_java
    $INSTALL_NODEJS && install_nodejs
    $INSTALL_RUST && install_rust
    $INSTALL_RUBY && install_ruby
    $INSTALL_DOCKER && install_docker
    
    print_success "所有选定的开发工具安装完成！"
    print_info "请重新登录或运行 'source /etc/profile' 以使环境变量生效"
    print_info "如果您安装了 NVM，请运行 'source ~/.bashrc' 以使 NVM 环境变量生效"
    print_info "如果您安装了 RVM，请运行 'source /etc/profile.d/rvm.sh' 以使 RVM 环境变量生效"
}

# 执行主函数
main


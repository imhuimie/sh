#!/bin/bash

# =========================================================
# Linux 通用开发环境一键安装脚本 V7.0 (安全重构版)
# 更新日志:
# V7.0: 修复安全隐患，环境变量写入 ~/.bashrc，增加备份机制
# =========================================================

set -o pipefail

# --- 全局配置 ---
SCRIPT_VERSION="7.0"
LOG_DIR="/var/log/dev_install"
LOG_FILE="${LOG_DIR}/install_$(date +%Y%m%d_%H%M%S).log"
BACKUP_DIR="/var/backup/dev_install"

# 安装基础目录
INSTALL_BASE="/opt/dev_tools"
PYTHON_HOME="${INSTALL_BASE}/python3"
GO_HOME="${INSTALL_BASE}/go"
NODE_HOME="${INSTALL_BASE}/nodejs"

# 环境变量标记（用于识别脚本添加的配置）
ENV_MARKER_START="# >>> dev_install_script >>>"
ENV_MARKER_END="# <<< dev_install_script <<<"

# --- 颜色定义 ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# =========================================================
# 日志函数（安全版本，不使用 exec 重定向）
# =========================================================

log_init() {
    mkdir -p "$LOG_DIR" "$BACKUP_DIR" "$INSTALL_BASE"
    chmod 755 "$LOG_DIR" "$BACKUP_DIR" "$INSTALL_BASE"
    touch "$LOG_FILE"
    chmod 644 "$LOG_FILE"
}

log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
  
    case $level in
        INFO)  echo -e "${GREEN}[INFO]${NC} $message" ;;
        WARN)  echo -e "${YELLOW}[WARN]${NC} $message" ;;
        ERROR) echo -e "${RED}[ERROR]${NC} $message" ;;
        DEBUG) echo -e "${CYAN}[DEBUG]${NC} $message" ;;
        *)     echo "$message" ;;
    esac
}

# =========================================================
# 基础检查
# =========================================================

check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}错误: 请使用 root 权限运行此脚本。${NC}"
        echo "用法: sudo $0"
        exit 1
    fi
}

check_arch() {
    ARCH=$(uname -m)
    case $ARCH in
        x86_64)
            GO_ARCH="amd64"
            NODE_ARCH="x64"
            ;;
        aarch64|arm64)
            GO_ARCH="arm64"
            NODE_ARCH="arm64"
            ;;
        armv7l)
            GO_ARCH="armv6l"
            NODE_ARCH="armv7l"
            ;;
        *)
            log ERROR "不支持的架构: $ARCH"
            exit 1
            ;;
    esac
    log INFO "检测到系统架构: $ARCH"
}

check_disk_space() {
    local required_mb=$1
    local target_dir=${2:-$INSTALL_BASE}
  
    # 确保目录存在
    mkdir -p "$target_dir" 2>/dev/null
  
    local available_kb=$(df "$target_dir" 2>/dev/null | tail -1 | awk '{print $4}')
    if [ -z "$available_kb" ]; then
        log WARN "无法检测磁盘空间，继续安装..."
        return 0
    fi
  
    local available_mb=$((available_kb / 1024))
    if [ "$available_mb" -lt "$required_mb" ]; then
        log ERROR "磁盘空间不足! 需要 ${required_mb}MB, 当前可用 ${available_mb}MB"
        return 1
    fi
    log INFO "磁盘空间检查通过: 可用 ${available_mb}MB"
    return 0
}

# =========================================================
# 网络与源配置
# =========================================================

check_region_and_config() {
    log INFO "正在检测网络环境..."
  
    # 尝试多个检测点
    local is_global=false
  
    for test_url in "https://www.google.com" "https://www.github.com" "https://go.dev"; do
        if curl -I -m 3 -s "$test_url" >/dev/null 2>&1; then
            is_global=true
            break
        fi
    done
  
    if $is_global; then
        REGION="GLOBAL"
        log INFO "网络判定: 国际/海外环境 (Global)"
      
        # 国际源配置
        URL_PY_BASE="https://www.python.org/ftp/python/"
        PIP_INDEX_URL="https://pypi.org/simple"
        PIP_TRUSTED_HOST="pypi.org"
      
        URL_GO_BASE="https://go.dev/dl/"
        GO_PROXY_VAL="https://proxy.golang.org,direct"
      
        URL_NODE_BASE="https://nodejs.org/dist/"
        NPM_REGISTRY="https://registry.npmjs.org/"
    else
        REGION="CN"
        log INFO "网络判定: 国内环境 (Mainland China)"
      
        # 国内源配置
        URL_PY_BASE="https://npmmirror.com/mirrors/python/"
        PIP_INDEX_URL="https://mirrors.aliyun.com/pypi/simple/"
        PIP_TRUSTED_HOST="mirrors.aliyun.com"
      
        URL_GO_BASE="https://mirrors.aliyun.com/golang/"
        GO_PROXY_VAL="https://goproxy.cn,direct"
      
        URL_NODE_BASE="https://npmmirror.com/mirrors/node/"
        NPM_REGISTRY="https://registry.npmmirror.com/"
    fi
}

# =========================================================
# 环境变量管理（安全版本）
# =========================================================

# 获取实际用户的家目录
get_real_user_home() {
    if [ -n "$SUDO_USER" ]; then
        REAL_USER="$SUDO_USER"
        REAL_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
    else
        REAL_USER="root"
        REAL_HOME="/root"
    fi
  
    if [ -z "$REAL_HOME" ] || [ ! -d "$REAL_HOME" ]; then
        REAL_HOME="/root"
        REAL_USER="root"
    fi
}

# 备份 bashrc
backup_bashrc() {
    local bashrc_file="$1"
    if [ -f "$bashrc_file" ]; then
        local backup_file="${BACKUP_DIR}/bashrc_$(date +%Y%m%d_%H%M%S).bak"
        cp "$bashrc_file" "$backup_file"
        log INFO "已备份 bashrc 到: $backup_file"
    fi
}

# 添加环境变量到 bashrc（安全方式）
add_env_to_bashrc() {
    local bashrc_file="$1"
    local env_content="$2"
  
    # 确保文件存在
    [ ! -f "$bashrc_file" ] && touch "$bashrc_file"
  
    # 备份
    backup_bashrc "$bashrc_file"
  
    # 检查是否已存在我们的配置块
    if grep -q "$ENV_MARKER_START" "$bashrc_file"; then
        # 移除旧的配置块
        remove_env_from_bashrc "$bashrc_file"
    fi
  
    # 添加新的配置块
    {
        echo ""
        echo "$ENV_MARKER_START"
        echo "# 由 dev_install_script v${SCRIPT_VERSION} 自动生成"
        echo "# 生成时间: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "$env_content"
        echo "$ENV_MARKER_END"
    } >> "$bashrc_file"
  
    log INFO "环境变量已添加到: $bashrc_file"
}

# 从 bashrc 移除环境变量（安全方式）
remove_env_from_bashrc() {
    local bashrc_file="$1"
  
    if [ ! -f "$bashrc_file" ]; then
        return 0
    fi
  
    if ! grep -q "$ENV_MARKER_START" "$bashrc_file"; then
        log WARN "未找到脚本添加的环境变量配置"
        return 0
    fi
  
    # 备份
    backup_bashrc "$bashrc_file"
  
    # 使用 awk 安全删除配置块
    local temp_file=$(mktemp)
    awk -v start="$ENV_MARKER_START" -v end="$ENV_MARKER_END" '
        $0 ~ start { skip=1; next }
        $0 ~ end { skip=0; next }
        !skip { print }
    ' "$bashrc_file" > "$temp_file"
  
    # 检查 awk 是否成功
    if [ $? -eq 0 ] && [ -s "$temp_file" ]; then
        mv "$temp_file" "$bashrc_file"
        log INFO "已移除环境变量配置"
    else
        rm -f "$temp_file"
        log ERROR "移除环境变量失败"
        return 1
    fi
}

# 更新所有用户的环境变量
update_all_env() {
    get_real_user_home
  
    local env_content=""
  
    # Python 环境
    if [ -d "$PYTHON_HOME/bin" ]; then
        env_content+="export PYTHON_HOME=\"$PYTHON_HOME\"\n"
        env_content+="export PATH=\"\$PYTHON_HOME/bin:\$PATH\"\n"
    fi
  
    # Go 环境
    if [ -d "$GO_HOME/bin" ]; then
        env_content+="export GOROOT=\"$GO_HOME\"\n"
        env_content+="export GOPATH=\"\$HOME/go\"\n"
        env_content+="export PATH=\"\$GOROOT/bin:\$GOPATH/bin:\$PATH\"\n"
        env_content+="export GOPROXY=\"$GO_PROXY_VAL\"\n"
    fi
  
    # Node 环境
    if [ -d "$NODE_HOME/bin" ]; then
        env_content+="export NODE_HOME=\"$NODE_HOME\"\n"
        env_content+="export PATH=\"\$NODE_HOME/bin:\$PATH\"\n"
    fi
  
    if [ -z "$env_content" ]; then
        log WARN "没有需要配置的环境变量"
        return 0
    fi
  
    # 更新当前用户的 bashrc
    add_env_to_bashrc "${REAL_HOME}/.bashrc" "$(echo -e "$env_content")"
  
    # 如果是 sudo 运行，也更新 root 的配置
    if [ "$REAL_USER" != "root" ]; then
        add_env_to_bashrc "/root/.bashrc" "$(echo -e "$env_content")"
    fi
  
    # 同时创建 /etc/profile.d 配置（系统级）
    local profile_script="/etc/profile.d/dev_tools.sh"
    {
        echo "#!/bin/bash"
        echo "# 由 dev_install_script v${SCRIPT_VERSION} 自动生成"
        echo -e "$env_content"
    } > "$profile_script"
    chmod 644 "$profile_script"
  
    log INFO "环境变量配置完成"
}

# =========================================================
# 下载函数
# =========================================================

download_file() {
    local url=$1
    local output_file=$2
    local max_retries=3
    local retry=0
  
    [ -z "$output_file" ] && output_file=$(basename "$url")
  
    log INFO "正在下载: $output_file"
    log DEBUG "下载地址: $url"
  
    while [ $retry -lt $max_retries ]; do
        if wget --no-check-certificate \
                --progress=bar:force:noscroll \
                --timeout=30 \
                --tries=1 \
                -O "$output_file" \
                "$url" 2>&1; then
          
            # 验证文件
            if [ -f "$output_file" ] && [ -s "$output_file" ]; then
                log INFO "下载完成: $output_file"
                return 0
            fi
        fi
      
        retry=$((retry + 1))
        log WARN "下载失败，重试 $retry/$max_retries..."
        sleep 2
    done
  
    log ERROR "下载失败: $url"
    rm -f "$output_file"
    return 1
}

# =========================================================
# 系统依赖安装
# =========================================================

install_deps() {
    if [ "$DEPS_INSTALLED" = "true" ]; then
        return 0
    fi
  
    log INFO "正在安装系统依赖..."
  
    # 检测系统类型
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_ID="$ID"
    elif [ -f /etc/redhat-release ]; then
        OS_ID="centos"
    else
        OS_ID="unknown"
    fi
  
    case "$OS_ID" in
        centos|rhel|fedora|rocky|almalinux|amzn)
            log INFO "检测到 RHEL 系列系统: $OS_ID"
            yum install -y wget curl git gcc make \
                zlib-devel bzip2-devel openssl-devel \
                ncurses-devel sqlite-devel readline-devel \
                tk-devel libffi-devel xz xz-devel \
                2>&1 | tee -a "$LOG_FILE"
            ;;
        debian|ubuntu|linuxmint|kali)
            log INFO "检测到 Debian 系列系统: $OS_ID"
            apt-get update 2>&1 | tee -a "$LOG_FILE"
            apt-get install -y wget curl git gcc make \
                build-essential libssl-dev zlib1g-dev \
                libbz2-dev libreadline-dev libsqlite3-dev \
                libncurses5-dev libncursesw5-dev xz-utils \
                tk-dev libffi-dev liblzma-dev \
                2>&1 | tee -a "$LOG_FILE"
            ;;
        opensuse*|sles)
            log INFO "检测到 SUSE 系列系统: $OS_ID"
            zypper install -y wget curl git gcc make \
                zlib-devel libbz2-devel libopenssl-devel \
                ncurses-devel sqlite3-devel readline-devel \
                tk-devel libffi-devel xz \
                2>&1 | tee -a "$LOG_FILE"
            ;;
        arch|manjaro)
            log INFO "检测到 Arch 系列系统: $OS_ID"
            pacman -Sy --noconfirm wget curl git gcc make \
                base-devel openssl zlib bzip2 readline \
                sqlite ncurses tk libffi xz \
                2>&1 | tee -a "$LOG_FILE"
            ;;
        *)
            log WARN "未识别的系统: $OS_ID，尝试通用安装..."
            if command -v yum &>/dev/null; then
                yum install -y wget curl git gcc make 2>&1 | tee -a "$LOG_FILE"
            elif command -v apt-get &>/dev/null; then
                apt-get update && apt-get install -y wget curl git gcc make 2>&1 | tee -a "$LOG_FILE"
            else
                log ERROR "无法安装依赖，请手动安装: wget curl git gcc make"
                return 1
            fi
            ;;
    esac
  
    export DEPS_INSTALLED=true
    log INFO "系统依赖安装完成"
}

# =========================================================
# 版本检测
# =========================================================

check_current_versions() {
    # Python
    if [ -x "$PYTHON_HOME/bin/python3" ]; then
        CUR_PY=$("$PYTHON_HOME/bin/python3" --version 2>&1 | awk '{print $2}')
        MSG_PY="${GREEN}${CUR_PY}${NC} (脚本安装)"
    elif command -v python3 &>/dev/null; then
        CUR_PY=$(python3 --version 2>&1 | awk '{print $2}')
        MSG_PY="${YELLOW}${CUR_PY}${NC} (系统自带)"
    else
        MSG_PY="${RED}未安装${NC}"
    fi
  
    # Go
    if [ -x "$GO_HOME/bin/go" ]; then
        CUR_GO=$("$GO_HOME/bin/go" version 2>&1 | awk '{print $3}' | sed 's/go//')
        MSG_GO="${GREEN}${CUR_GO}${NC}"
    elif command -v go &>/dev/null; then
        CUR_GO=$(go version 2>&1 | awk '{print $3}' | sed 's/go//')
        MSG_GO="${YELLOW}${CUR_GO}${NC} (其他来源)"
    else
        MSG_GO="${RED}未安装${NC}"
    fi
  
    # Node
    if [ -x "$NODE_HOME/bin/node" ]; then
        CUR_NODE=$("$NODE_HOME/bin/node" -v 2>&1)
        MSG_NODE="${GREEN}${CUR_NODE}${NC}"
    elif command -v node &>/dev/null; then
        CUR_NODE=$(node -v 2>&1)
        MSG_NODE="${YELLOW}${CUR_NODE}${NC} (其他来源)"
    else
        MSG_NODE="${RED}未安装${NC}"
    fi
}

# =========================================================
# 安装函数
# =========================================================

install_python() {
    echo -e "\n${CYAN}=== 安装 Python ===${NC}"
    log INFO "开始安装 Python..."
  
    check_disk_space 1500 "$INSTALL_BASE" || return 1
    install_deps || return 1
  
    # 获取可用版本
    echo -e "${BLUE}正在获取可用版本列表...${NC}"
    local versions=""
  
    if [ "$REGION" = "CN" ]; then
        versions=$(curl -s --connect-timeout 10 "$URL_PY_BASE" | \
            grep -oP '3\.\d+\.\d+' | sort -V | uniq | tail -10)
    else
        versions=$(curl -s --connect-timeout 10 "$URL_PY_BASE" | \
            grep -oP 'href="3\.\d+\.\d+/"' | grep -oP '3\.\d+\.\d+' | sort -V | uniq | tail -10)
    fi
  
    local latest_ver=$(echo "$versions" | tail -1)
    [ -z "$latest_ver" ] && latest_ver="3.12.3"
  
    if [ -n "$versions" ]; then
        echo -e "${GREEN}可用版本:${NC}"
        echo "$versions" | tail -5 | while read v; do echo "  - $v"; done
    fi
  
    read -p "请输入要安装的版本 (默认: $latest_ver): " py_version
    [ -z "$py_version" ] && py_version="$latest_ver"
  
    log INFO "选择安装 Python $py_version"
  
    # 创建临时目录
    local work_dir=$(mktemp -d)
    cd "$work_dir" || return 1
  
    # 下载
    local py_file="Python-${py_version}.tgz"
    local download_url="${URL_PY_BASE}${py_version}/${py_file}"
  
    download_file "$download_url" "$py_file" || {
        cd /
        rm -rf "$work_dir"
        return 1
    }
  
    # 解压
    log INFO "正在解压..."
    tar -xzf "$py_file" || {
        log ERROR "解压失败"
        cd /
        rm -rf "$work_dir"
        return 1
    }
  
    cd "Python-${py_version}" || return 1
  
    # 编译安装
    log INFO "正在配置编译选项..."
    ./configure --prefix="$PYTHON_HOME" \
                --enable-optimizations \
                --with-ssl \
                --enable-shared \
                LDFLAGS="-Wl,-rpath,$PYTHON_HOME/lib" \
                2>&1 | tee -a "$LOG_FILE"
  
    if [ $? -ne 0 ]; then
        log ERROR "配置失败"
        cd /
        rm -rf "$work_dir"
        return 1
    fi
  
    log INFO "正在编译（这可能需要几分钟）..."
    local cpu_count=$(nproc 2>/dev/null || echo 2)
    make -j"$cpu_count" 2>&1 | tee -a "$LOG_FILE"
  
    if [ $? -ne 0 ]; then
        log ERROR "编译失败"
        cd /
        rm -rf "$work_dir"
        return 1
    fi
  
    log INFO "正在安装..."
    make altinstall 2>&1 | tee -a "$LOG_FILE"
  
    if [ $? -ne 0 ]; then
        log ERROR "安装失败"
        cd /
        rm -rf "$work_dir"
        return 1
    fi
  
    # 创建软链接（在安装目录内，不覆盖系统命令）
    local py_major_minor=$(echo "$py_version" | cut -d. -f1,2)
    ln -sf "$PYTHON_HOME/bin/python${py_major_minor}" "$PYTHON_HOME/bin/python3"
    ln -sf "$PYTHON_HOME/bin/pip${py_major_minor}" "$PYTHON_HOME/bin/pip3"
    ln -sf "$PYTHON_HOME/bin/python${py_major_minor}" "$PYTHON_HOME/bin/python"
    ln -sf "$PYTHON_HOME/bin/pip${py_major_minor}" "$PYTHON_HOME/bin/pip"
  
    # 配置 pip 源
    get_real_user_home
    local pip_conf_dir="${REAL_HOME}/.pip"
    mkdir -p "$pip_conf_dir"
    cat > "${pip_conf_dir}/pip.conf" << EOF
[global]
index-url = $PIP_INDEX_URL
trusted-host = $PIP_TRUSTED_HOST
timeout = 120
EOF
    chown -R "$REAL_USER:$REAL_USER" "$pip_conf_dir" 2>/dev/null
  
    # 升级 pip
    "$PYTHON_HOME/bin/pip3" install --upgrade pip 2>&1 | tee -a "$LOG_FILE"
  
    # 清理
    cd /
    rm -rf "$work_dir"
  
    # 更新环境变量
    update_all_env
  
    log INFO "Python $py_version 安装完成!"
    echo -e "${GREEN}Python $py_version 安装成功!${NC}"
    echo -e "${YELLOW}请运行以下命令使环境变量生效:${NC}"
    echo -e "  source ~/.bashrc"
}

install_golang() {
    echo -e "\n${CYAN}=== 安装 Golang ===${NC}"
    log INFO "开始安装 Golang..."
  
    check_disk_space 500 "$INSTALL_BASE" || return 1
  
    # 获取最新版本
    local latest_ver=""
    if [ "$REGION" = "GLOBAL" ]; then
        latest_ver=$(curl -s "https://go.dev/VERSION?m=text" 2>/dev/null | head -1 | sed 's/go//')
    fi
    [ -z "$latest_ver" ] && latest_ver="1.22.2"
  
    echo -e "${GREEN}最新稳定版: $latest_ver${NC}"
    read -p "请输入要安装的版本 (默认: $latest_ver): " go_version
    [ -z "$go_version" ] && go_version="$latest_ver"
  
    # 清理版本号格式
    go_version=${go_version#v}
    go_version=${go_version#go}
  
    log INFO "选择安装 Go $go_version"
  
    local work_dir=$(mktemp -d)
    cd "$work_dir" || return 1
  
    local go_file="go${go_version}.linux-${GO_ARCH}.tar.gz"
    local download_url="${URL_GO_BASE}${go_file}"
  
    download_file "$download_url" "$go_file" || {
        cd /
        rm -rf "$work_dir"
        return 1
    }
  
    # 备份旧版本
    if [ -d "$GO_HOME" ]; then
        log INFO "备份旧版本..."
        mv "$GO_HOME" "${GO_HOME}.bak.$(date +%Y%m%d%H%M%S)"
    fi
  
    # 解压安装
    log INFO "正在安装..."
    mkdir -p "$(dirname "$GO_HOME")"
    tar -xzf "$go_file" -C "$(dirname "$GO_HOME")" || {
        log ERROR "解压失败"
        cd /
        rm -rf "$work_dir"
        return 1
    }
  
    # 如果解压目录名不是我们预期的，重命名
    if [ -d "$(dirname "$GO_HOME")/go" ] && [ "$(dirname "$GO_HOME")/go" != "$GO_HOME" ]; then
        mv "$(dirname "$GO_HOME")/go" "$GO_HOME"
    fi
  
    # 验证安装
    if [ ! -x "$GO_HOME/bin/go" ]; then
        log ERROR "安装验证失败"
        cd /
        rm -rf "$work_dir"
        return 1
    fi
  
    # 创建 GOPATH
    get_real_user_home
    mkdir -p "${REAL_HOME}/go"/{bin,src,pkg}
    chown -R "$REAL_USER:$REAL_USER" "${REAL_HOME}/go" 2>/dev/null
  
    # 清理
    cd /
    rm -rf "$work_dir"
  
    # 更新环境变量
    update_all_env
  
    log INFO "Golang $go_version 安装完成!"
    echo -e "${GREEN}Golang $go_version 安装成功!${NC}"
    echo -e "${YELLOW}请运行以下命令使环境变量生效:${NC}"
    echo -e "  source ~/.bashrc"
}

install_nodejs() {
    echo -e "\n${CYAN}=== 安装 Node.js ===${NC}"
    log INFO "开始安装 Node.js..."
  
    check_disk_space 300 "$INSTALL_BASE" || return 1
  
    # 检查 Glibc 版本
    local glibc_ver=$(ldd --version 2>&1 | head -1 | grep -oP '\d+\.\d+$' || echo "2.17")
    log INFO "系统 Glibc 版本: $glibc_ver"
  
    # 获取版本列表
    local default_ver="v20.12.0"
    echo -e "${GREEN}推荐版本: LTS (v20.x)${NC}"
    echo -e "${YELLOW}注意: Node.js 18+ 需要 Glibc 2.28+, 当前: $glibc_ver${NC}"
  
    read -p "请输入要安装的版本 (默认: $default_ver): " node_version
    [ -z "$node_version" ] && node_version="$default_ver"
  
    # 确保版本号格式正确
    [[ ! "$node_version" =~ ^v ]] && node_version="v$node_version"
  
    # Glibc 兼容性检查
    local major_ver=$(echo "$node_version" | sed 's/v//' | cut -d. -f1)
    if [ "$major_ver" -ge 18 ]; then
        local glibc_major=$(echo "$glibc_ver" | cut -d. -f1)
        local glibc_minor=$(echo "$glibc_ver" | cut -d. -f2)
        if [ "$glibc_major" -lt 2 ] || ([ "$glibc_major" -eq 2 ] && [ "$glibc_minor" -lt 28 ]); then
            echo -e "${RED}警告: Glibc 版本 ($glibc_ver) 可能不兼容 Node.js $node_version${NC}"
            echo -e "${YELLOW}建议使用 Node.js v16.x 或更低版本${NC}"
            read -p "是否继续安装? [y/N]: " confirm
            [[ ! "$confirm" =~ ^[Yy]$ ]] && return 1
        fi
    fi
  
  # --- 补全 install_nodejs 的剩余部分 ---
    
    log INFO "选择安装 Node.js $node_version"

    local work_dir=$(mktemp -d)
    cd "$work_dir" || return 1

    local node_file="node-${node_version}-linux-${NODE_ARCH}.tar.xz"
    local download_url="${URL_NODE_BASE}${node_version}/${node_file}"

    download_file "$download_url" "$node_file" || {
        cd /
        rm -rf "$work_dir"
        return 1
    }

    # 解压
    log INFO "正在解压..."
    mkdir -p "$NODE_HOME"
    # --strip-components 1 用于去除解压后的顶层目录
    tar -xJf "$node_file" -C "$NODE_HOME" --strip-components 1 || {
        log ERROR "解压失败"
        cd /
        rm -rf "$work_dir"
        return 1
    }

    # 验证
    if [ ! -x "$NODE_HOME/bin/node" ]; then
        log ERROR "安装验证失败"
        cd /
        rm -rf "$work_dir"
        return 1
    fi

    # 配置 npm 镜像
    if [ "$REGION" = "CN" ]; then
        "$NODE_HOME/bin/npm" config set registry "$NPM_REGISTRY"
        log INFO "已设置 npm 镜像源: $NPM_REGISTRY"
    fi

    # 清理
    cd /
    rm -rf "$work_dir"

    # 更新环境变量
    update_all_env

    log INFO "Node.js $node_version 安装完成!"
    echo -e "${GREEN}Node.js $node_version 安装成功!${NC}"
    echo -e "${YELLOW}请运行以下命令使环境变量生效:${NC}"
    echo -e "  source ~/.bashrc"
}

# =========================================================
# 主菜单逻辑 (Main Menu)
# =========================================================

show_menu() {
    clear
    echo -e "${BLUE}=========================================================${NC}"
    echo -e "   Linux 开发环境一键安装脚本 V${SCRIPT_VERSION} ${YELLOW}[安全重构版]${NC}"
    echo -e "${BLUE}=========================================================${NC}"
    echo -e "系统信息: $(uname -s) $(uname -m)"
    echo -e "当前用户: $USER (Root: $([ "$EUID" -eq 0 ] && echo "是" || echo "否"))"
    echo -e "安装路径: $INSTALL_BASE"
    echo -e "---------------------------------------------------------"
    
    check_current_versions
    
    echo -e " Python3: $MSG_PY"
    echo -e " Golang:  $MSG_GO"
    echo -e " Node.js: $MSG_NODE"
    echo -e "---------------------------------------------------------"
    echo -e " 1. 安装/更新 Python3"
    echo -e " 2. 安装/更新 Golang"
    echo -e " 3. 安装/更新 Node.js"
    echo -e " 4. 安装全部 (Python + Go + Node)"
    echo -e " 5. 修复/刷新环境变量"
    echo -e " 0. 退出脚本"
    echo -e "---------------------------------------------------------"
}

main() {
    log_init
    check_root
    check_arch
    check_region_and_config
    
    # 首次运行时安装依赖
    if [ -z "$DEPS_INSTALLED" ]; then
        install_deps
    fi

    while true; do
        show_menu
        read -p "请输入选项 [0-5]: " choice
        
        case $choice in
            1) install_python ;;
            2) install_golang ;;
            3) install_nodejs ;;
            4) 
               install_python
               install_golang
               install_nodejs
               ;;
            5) update_all_env ;;
            0) 
               echo "退出脚本。"
               exit 0 
               ;;
            *) echo -e "${RED}无效选项，请重新输入。${NC}"; sleep 1 ;;
        esac
        
        echo -e "\n${CYAN}按 Enter 键返回主菜单...${NC}"
        read
    done
}

# 执行主函数
main

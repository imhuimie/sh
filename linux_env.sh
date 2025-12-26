#!/bin/bash

# =========================================================
# Linux 通用开发环境一键安装脚本 V7.1 (支持自定义路径)
# 更新日志:
# V7.0: 修复安全隐患，环境变量写入 ~/.bashrc，增加备份机制
# V7.1: 新增自定义安装路径功能，优化路径变量处理逻辑
# =========================================================

set -o pipefail

# --- 全局配置 ---
SCRIPT_VERSION="7.1"
LOG_DIR="/var/log/dev_install"
# 确保日志目录存在 (如果不是 root 运行可能需要调整，这里假设 sudo)
mkdir -p "$LOG_DIR" 2>/dev/null || LOG_DIR="/tmp/dev_install_logs"
LOG_FILE="${LOG_DIR}/install_$(date +%Y%m%d_%H%M%S).log"
BACKUP_DIR="/var/backup/dev_install"

# 默认安装目录
DEFAULT_INSTALL_BASE="/opt/dev_tools"
INSTALL_BASE="$DEFAULT_INSTALL_BASE"

# 初始化子目录变量
update_paths() {
    PYTHON_HOME="${INSTALL_BASE}/python3"
    GO_HOME="${INSTALL_BASE}/go"
    NODE_HOME="${INSTALL_BASE}/nodejs"
}
# 初始执行一次
update_paths

# 环境变量标记
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
# 日志函数
# =========================================================

log_init() {
    # 只创建日志和备份目录，安装目录在安装时创建
    mkdir -p "$LOG_DIR" "$BACKUP_DIR"
    chmod 755 "$LOG_DIR" "$BACKUP_DIR" 2>/dev/null
    touch "$LOG_FILE"
    chmod 644 "$LOG_FILE" 2>/dev/null
}

log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    # 确保日志文件可写
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE" 2>/dev/null
   
    case $level in
        INFO)  echo -e "${GREEN}[INFO]${NC} $message" ;;
        WARN)  echo -e "${YELLOW}[WARN]${NC} $message" ;;
        ERROR) echo -e "${RED}[ERROR]${NC} $message" ;;
        DEBUG) echo -e "${CYAN}[DEBUG]${NC} $message" ;;
        *)     echo "$message" ;;
    esac
}

# =========================================================
# 路径设置函数 (新增)
# =========================================================

set_custom_path() {
    echo -e "\n${CYAN}=== 设置自定义安装目录 ===${NC}"
    echo -e "当前安装目录: ${GREEN}${INSTALL_BASE}${NC}"
    echo -e "${YELLOW}注意: 修改目录后，新安装的工具将位于新目录中。${NC}"
    echo -e "${YELLOW}      脚本会自动处理环境变量，但旧目录的残留文件需手动清理。${NC}"
    
    read -p "请输入新的绝对路径 (留空取消): " new_path
    
    if [ -z "$new_path" ]; then
        log INFO "取消修改路径"
        return
    fi

    # 简单验证路径合法性 (必须以 / 开头，不能包含空格)
    if [[ ! "$new_path" =~ ^/ ]]; then
        log ERROR "路径必须是绝对路径 (以 / 开头)"
        return
    fi
    
    if [[ "$new_path" =~ \  ]]; then
        log ERROR "路径不能包含空格"
        return
    fi

    # 确认
    echo -e "即将将安装路径修改为: ${RED}${new_path}${NC}"
    read -p "确认修改吗? [y/N]: " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        return
    fi

    INSTALL_BASE="$new_path"
    update_paths
    
    log INFO "安装目录已更新为: $INSTALL_BASE"
    echo -e "${GREEN}设置成功!${NC}"
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
    if ! mkdir -p "$target_dir" 2>/dev/null; then
        log ERROR "无法创建目录: $target_dir (权限不足或只读文件系统)"
        return 1
    fi
   
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
    log INFO "磁盘空间检查通过 ($target_dir): 可用 ${available_mb}MB"
    return 0
}

# =========================================================
# 网络与源配置
# =========================================================

check_region_and_config() {
    log INFO "正在检测网络环境..."
   
    local is_global=false
   
    for test_url in "https://www.google.com" "https://www.github.com" "https://go.dev"; do
        if curl -I -m 2 -s "$test_url" >/dev/null 2>&1; then
            is_global=true
            break
        fi
    done
   
    if $is_global; then
        REGION="GLOBAL"
        log INFO "网络判定: 国际/海外环境 (Global)"
       
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
# 环境变量管理
# =========================================================

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

backup_bashrc() {
    local bashrc_file="$1"
    if [ -f "$bashrc_file" ]; then
        local backup_file="${BACKUP_DIR}/bashrc_$(date +%Y%m%d_%H%M%S).bak"
        cp "$bashrc_file" "$backup_file"
        log INFO "已备份 bashrc 到: $backup_file"
    fi
}

add_env_to_bashrc() {
    local bashrc_file="$1"
    local env_content="$2"
   
    [ ! -f "$bashrc_file" ] && touch "$bashrc_file"
    backup_bashrc "$bashrc_file"
   
    if grep -q "$ENV_MARKER_START" "$bashrc_file"; then
        remove_env_from_bashrc "$bashrc_file"
    fi
   
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

remove_env_from_bashrc() {
    local bashrc_file="$1"
   
    if [ ! -f "$bashrc_file" ]; then return 0; fi
    if ! grep -q "$ENV_MARKER_START" "$bashrc_file"; then return 0; fi
   
    local temp_file=$(mktemp)
    awk -v start="$ENV_MARKER_START" -v end="$ENV_MARKER_END" '
        $0 ~ start { skip=1; next }
        $0 ~ end { skip=0; next }
        !skip { print }
    ' "$bashrc_file" > "$temp_file"
   
    if [ $? -eq 0 ] && [ -s "$temp_file" ]; then
        mv "$temp_file" "$bashrc_file"
        chown "$REAL_USER" "$bashrc_file" 2>/dev/null
    else
        rm -f "$temp_file"
    fi
}

update_all_env() {
    get_real_user_home
   
    local env_content=""
   
    # 这里检测的是当前配置的路径下是否有 bin 目录
    # 如果用户改了路径但未安装，这里不会写入乱码
    
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
        log WARN "当前目录($INSTALL_BASE)下未检测到已安装的工具，跳过环境变量更新"
        return 0
    fi
   
    add_env_to_bashrc "${REAL_HOME}/.bashrc" "$(echo -e "$env_content")"
   
    if [ "$REAL_USER" != "root" ]; then
        add_env_to_bashrc "/root/.bashrc" "$(echo -e "$env_content")"
    fi
   
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
   
    while [ $retry -lt $max_retries ]; do
        if wget --no-check-certificate \
                --progress=bar:force:noscroll \
                --timeout=30 \
                --tries=1 \
                -O "$output_file" \
                "$url" 2>&1; then
           
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
    if [ "$DEPS_INSTALLED" = "true" ]; then return 0; fi
    log INFO "正在安装系统依赖..."
   
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_ID="$ID"
    else
        OS_ID="unknown"
    fi
   
    case "$OS_ID" in
        centos|rhel|fedora|rocky|almalinux|amzn)
            yum install -y wget curl git gcc make zlib-devel bzip2-devel openssl-devel \
                ncurses-devel sqlite-devel readline-devel tk-devel libffi-devel xz xz-devel \
                2>&1 | tee -a "$LOG_FILE"
            ;;
        debian|ubuntu|linuxmint|kali)
            apt-get update 2>&1 | tee -a "$LOG_FILE"
            apt-get install -y wget curl git gcc make build-essential libssl-dev zlib1g-dev \
                libbz2-dev libreadline-dev libsqlite3-dev libncurses5-dev libncursesw5-dev \
                xz-utils tk-dev libffi-dev liblzma-dev \
                2>&1 | tee -a "$LOG_FILE"
            ;;
        arch|manjaro)
            pacman -Sy --noconfirm wget curl git gcc make base-devel openssl zlib bzip2 \
                readline sqlite ncurses tk libffi xz \
                2>&1 | tee -a "$LOG_FILE"
            ;;
        *)
            if command -v yum &>/dev/null; then
                yum install -y wget curl git gcc make 2>&1 | tee -a "$LOG_FILE"
            elif command -v apt-get &>/dev/null; then
                apt-get update && apt-get install -y wget curl git gcc make 2>&1 | tee -a "$LOG_FILE"
            fi
            ;;
    esac
    export DEPS_INSTALLED=true
}

# =========================================================
# 版本检测
# =========================================================

check_current_versions() {
    # 检测逻辑：优先检测脚本当前配置路径下的版本，其次检测系统全局版本
    
    # Python
    if [ -x "$PYTHON_HOME/bin/python3" ]; then
        CUR_PY=$("$PYTHON_HOME/bin/python3" --version 2>&1 | awk '{print $2}')
        MSG_PY="${GREEN}${CUR_PY}${NC} (已安装于当前目录)"
    elif command -v python3 &>/dev/null; then
        CUR_PY=$(python3 --version 2>&1 | awk '{print $2}')
        MSG_PY="${YELLOW}${CUR_PY}${NC} (系统/其他位置)"
    else
        MSG_PY="${RED}未安装${NC}"
    fi
   
    # Go
    if [ -x "$GO_HOME/bin/go" ]; then
        CUR_GO=$("$GO_HOME/bin/go" version 2>&1 | awk '{print $3}' | sed 's/go//')
        MSG_GO="${GREEN}${CUR_GO}${NC} (已安装于当前目录)"
    elif command -v go &>/dev/null; then
        CUR_GO=$(go version 2>&1 | awk '{print $3}' | sed 's/go//')
        MSG_GO="${YELLOW}${CUR_GO}${NC} (系统/其他位置)"
    else
        MSG_GO="${RED}未安装${NC}"
    fi
   
    # Node
    if [ -x "$NODE_HOME/bin/node" ]; then
        CUR_NODE=$("$NODE_HOME/bin/node" -v 2>&1)
        MSG_NODE="${GREEN}${CUR_NODE}${NC} (已安装于当前目录)"
    elif command -v node &>/dev/null; then
        CUR_NODE=$(node -v 2>&1)
        MSG_NODE="${YELLOW}${CUR_NODE}${NC} (系统/其他位置)"
    else
        MSG_NODE="${RED}未安装${NC}"
    fi
}

# =========================================================
# 安装函数
# =========================================================

install_python() {
    echo -e "\n${CYAN}=== 安装 Python ===${NC}"
    echo -e "安装路径: $PYTHON_HOME"
    
    check_disk_space 1500 "$INSTALL_BASE" || return 1
    install_deps || return 1
   
    echo -e "${BLUE}正在获取可用版本列表...${NC}"
    local versions=""
    if [ "$REGION" = "CN" ]; then
        versions=$(curl -s --connect-timeout 5 "$URL_PY_BASE" | grep -oP '3\.\d+\.\d+' | sort -V | uniq | tail -10)
    else
        versions=$(curl -s --connect-timeout 5 "$URL_PY_BASE" | grep -oP 'href="3\.\d+\.\d+/"' | grep -oP '3\.\d+\.\d+' | sort -V | uniq | tail -10)
    fi
    local latest_ver=$(echo "$versions" | tail -1)
    [ -z "$latest_ver" ] && latest_ver="3.12.3"
    
    if [ -n "$versions" ]; then
        echo -e "${GREEN}最近版本:${NC}"
        echo "$versions" | tail -5 | while read v; do echo "  - $v"; done
    fi
    
    read -p "请输入版本 (默认: $latest_ver): " py_version
    [ -z "$py_version" ] && py_version="$latest_ver"
    log INFO "开始安装 Python $py_version 到 $PYTHON_HOME"
   
    local work_dir=$(mktemp -d)
    cd "$work_dir" || return 1
   
    local py_file="Python-${py_version}.tgz"
    download_file "${URL_PY_BASE}${py_version}/${py_file}" "$py_file" || { cd /; rm -rf "$work_dir"; return 1; }
   
    log INFO "解压中..."
    tar -xzf "$py_file" || { log ERROR "解压失败"; cd /; rm -rf "$work_dir"; return 1; }
    cd "Python-${py_version}" || return 1
   
    log INFO "配置编译选项..."
    # 确保目录存在
    mkdir -p "$PYTHON_HOME"
    
    ./configure --prefix="$PYTHON_HOME" \
                --enable-optimizations \
                --with-ssl \
                --enable-shared \
                LDFLAGS="-Wl,-rpath,$PYTHON_HOME/lib" \
                2>&1 | tee -a "$LOG_FILE"
   
    if [ $? -ne 0 ]; then log ERROR "配置失败"; cd /; rm -rf "$work_dir"; return 1; fi
   
    log INFO "编译中 (需要几分钟)..."
    make -j"$(nproc 2>/dev/null || echo 2)" 2>&1 | tee -a "$LOG_FILE"
    if [ $? -ne 0 ]; then log ERROR "编译失败"; cd /; rm -rf "$work_dir"; return 1; fi
   
    log INFO "安装中..."
    make altinstall 2>&1 | tee -a "$LOG_FILE"
   
    # 软链接处理
    local py_major_minor=$(echo "$py_version" | cut -d. -f1,2)
    ln -sf "$PYTHON_HOME/bin/python${py_major_minor}" "$PYTHON_HOME/bin/python3"
    ln -sf "$PYTHON_HOME/bin/pip${py_major_minor}" "$PYTHON_HOME/bin/pip3"
    ln -sf "$PYTHON_HOME/bin/python3" "$PYTHON_HOME/bin/python"
    ln -sf "$PYTHON_HOME/bin/pip3" "$PYTHON_HOME/bin/pip"
   
    # 配置 pip
    get_real_user_home
    mkdir -p "${REAL_HOME}/.pip"
    cat > "${REAL_HOME}/.pip/pip.conf" << EOF
[global]
index-url = $PIP_INDEX_URL
trusted-host = $PIP_TRUSTED_HOST
timeout = 120
EOF
    chown -R "$REAL_USER:$REAL_USER" "${REAL_HOME}/.pip" 2>/dev/null
    "$PYTHON_HOME/bin/pip3" install --upgrade pip 2>&1 | tee -a "$LOG_FILE"
   
    cd /
    rm -rf "$work_dir"
    update_all_env
    echo -e "${GREEN}Python $py_version 安装成功!${NC}"
}

install_golang() {
    echo -e "\n${CYAN}=== 安装 Golang ===${NC}"
    echo -e "安装路径: $GO_HOME"
    
    check_disk_space 500 "$INSTALL_BASE" || return 1
   
    local latest_ver=""
    if [ "$REGION" = "GLOBAL" ]; then
        latest_ver=$(curl -s "https://go.dev/VERSION?m=text" 2>/dev/null | head -1 | sed 's/go//')
    fi
    [ -z "$latest_ver" ] && latest_ver="1.22.2"
   
    read -p "请输入版本 (默认: $latest_ver): " go_version
    [ -z "$go_version" ] && go_version="$latest_ver"
    go_version=${go_version#v}
    go_version=${go_version#go}
   
    log INFO "开始安装 Go $go_version 到 $GO_HOME"
    local work_dir=$(mktemp -d)
    cd "$work_dir" || return 1
   
    local go_file="go${go_version}.linux-${GO_ARCH}.tar.gz"
    download_file "${URL_GO_BASE}${go_file}" "$go_file" || { cd /; rm -rf "$work_dir"; return 1; }
   
    if [ -d "$GO_HOME" ]; then
        log INFO "备份旧版本..."
        mv "$GO_HOME" "${GO_HOME}.bak.$(date +%Y%m%d%H%M%S)"
    fi
   
    log INFO "解压安装..."
    mkdir -p "$(dirname "$GO_HOME")"
    tar -xzf "$go_file" -C "$(dirname "$GO_HOME")"
   
    # 修正目录名 (如果解压出来是 go，但我们想要 custom_path/go，通常 tar 解压出来是 go)
    # 如果用户设定的 GO_HOME 名字不是 go (例如 /opt/golang)，需要重命名
    local extract_dir="$(dirname "$GO_HOME")/go"
    if [ -d "$extract_dir" ] && [ "$extract_dir" != "$GO_HOME" ]; then
        mv "$extract_dir" "$GO_HOME"
    fi
   
    # 创建 GOPATH
    get_real_user_home
    mkdir -p "${REAL_HOME}/go"/{bin,src,pkg}
    chown -R "$REAL_USER:$REAL_USER" "${REAL_HOME}/go" 2>/dev/null
   
    cd /
    rm -rf "$work_dir"
    update_all_env
    echo -e "${GREEN}Golang $go_version 安装成功!${NC}"
}

install_nodejs() {
    echo -e "\n${CYAN}=== 安装 Node.js ===${NC}"
    echo -e "安装路径: $NODE_HOME"
    
    check_disk_space 300 "$INSTALL_BASE" || return 1
    
    local glibc_ver=$(ldd --version 2>&1 | head -1 | grep -oP '\d+\.\d+$' || echo "2.17")
    echo -e "系统 Glibc: $glibc_ver"
   
    local default_ver="v20.12.0"
    read -p "请输入版本 (默认: $default_ver): " node_version
    [ -z "$node_version" ] && node_version="$default_ver"
    [[ ! "$node_version" =~ ^v ]] && node_version="v$node_version"
   
    log INFO "开始安装 Node.js $node_version 到 $NODE_HOME"
    local work_dir=$(mktemp -d)
    cd "$work_dir" || return 1
   
    local node_file="node-${node_version}-linux-${NODE_ARCH}.tar.xz"
    download_file "${URL_NODE_BASE}${node_version}/${node_file}" "$node_file" || { cd /; rm -rf "$work_dir"; return 1; }
   
    mkdir -p "$NODE_HOME"
    tar -xJf "$node_file" -C "$NODE_HOME" --strip-components 1
   
    if [ "$REGION" = "CN" ]; then
        "$NODE_HOME/bin/npm" config set registry "$NPM_REGISTRY"
    fi
   
    cd /
    rm -rf "$work_dir"
    update_all_env
    echo -e "${GREEN}Node.js $node_version 安装成功!${NC}"
}

# =========================================================
# 主菜单逻辑
# =========================================================

show_menu() {
    clear
    echo -e "${BLUE}=========================================================${NC}"
    echo -e "  Linux 开发环境一键安装脚本 V${SCRIPT_VERSION} ${YELLOW}[支持自定义路径]${NC}"
    echo -e "${BLUE}=========================================================${NC}"
    echo -e "系统信息: $(uname -s) $(uname -m)"
    echo -e "当前用户: $USER"
    echo -e "安装根目录: ${CYAN}${INSTALL_BASE}${NC}"
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
    echo -e " 6. [设置] 修改安装目录"
    echo -e " 0. 退出脚本"
    echo -e "---------------------------------------------------------"
}

main() {
    log_init
    check_root
    check_arch
    check_region_and_config
    
    # 首次运行时简单检查依赖
    if [ -z "$DEPS_INSTALLED" ]; then
        # 这里只做轻量检查，真正安装在 install_python 等函数中会调用
        if ! command -v wget &>/dev/null; then install_deps; fi
    fi

    while true; do
        show_menu
        read -p "请输入选项 [0-6]: " choice
        
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
            6) set_custom_path ;;
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

main

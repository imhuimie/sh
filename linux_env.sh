#!/bin/bash

# =========================================================
# Linux 通用开发环境一键安装脚本 V4.0 (运维全能版)
# =========================================================

# --- 日志配置 ---
LOG_DIR="/var/log"
LOG_PREFIX="dev_install_"
CURRENT_LOG_NAME="${LOG_PREFIX}$(date +%Y%m%d_%H%M%S).log"
LOG_FILE="${LOG_DIR}/${CURRENT_LOG_NAME}"

# 重定向输出
exec 1> >(tee -a "$LOG_FILE")
exec 2>&1

# 定义颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 网络配置
CURL_OPTS="--connect-timeout 10 --max-time 30 -s"

# 检查 root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}请使用 root 权限运行.${NC}"
  exit 1
fi

# 架构判断
ARCH=$(uname -m)
case $ARCH in
  x86_64)  GO_ARCH="amd64"; NODE_ARCH="x64" ;;
  aarch64) GO_ARCH="arm64"; NODE_ARCH="arm64" ;;
  *)       echo -e "${RED}不支持的架构: $ARCH${NC}"; exit 1 ;;
esac

# =========================================================
# 核心功能函数
# =========================================================

check_disk_space() {
    local required_mb=$1
    local available_kb=$(df /usr/local | tail -1 | awk '{print $4}')
    local available_mb=$((available_kb / 1024))
    if [ "$available_mb" -lt "$required_mb" ]; then
        echo -e "${RED}磁盘空间不足! 需 ${required_mb}MB, 剩 ${available_mb}MB${NC}"
        return 1
    fi
    echo -e "${GREEN}磁盘空间充足 (${available_mb}MB)${NC}"
    return 0
}

download_file() {
    local url=$1
    local filename=$2
    [ -z "$filename" ] && filename="${url##*/}"
    local retries=3
    echo -e "${BLUE}下载: $filename${NC}"
    while [ $retries -gt 0 ]; do
        wget --no-check-certificate --timeout=30 -O "$filename" "$url"
        [ $? -eq 0 ] && echo -e "${GREEN}下载成功${NC}" && return 0
        echo -e "${YELLOW}重试中 ($((retries-1)))...${NC}"
        ((retries--))
        sleep 2
    done
    echo -e "${RED}下载失败${NC}"; return 1
}

check_current_versions() {
    if command -v python3 >/dev/null 2>&1; then
        CUR_PY=$(python3 --version | awk '{print $2}')
        MSG_PY="${GREEN}${CUR_PY}${NC}"
    else
        CUR_PY=""; MSG_PY="${RED}未安装${NC}"
    fi

    if command -v go >/dev/null 2>&1; then
        CUR_GO=$(go version | awk '{print $3}' | sed 's/go//')
        MSG_GO="${GREEN}${CUR_GO}${NC}"
    else
        CUR_GO=""; MSG_GO="${RED}未安装${NC}"
    fi

    if command -v node >/dev/null 2>&1; then
        CUR_NODE=$(node -v)
        MSG_NODE="${GREEN}${CUR_NODE}${NC}"
    else
        CUR_NODE=""; MSG_NODE="${RED}未安装${NC}"
    fi
}

install_deps() {
  if [ -z "$DEPS_INSTALLED" ]; then
    echo -e "${BLUE}检查基础依赖...${NC}"
    if [ -f /etc/redhat-release ]; then
      yum install -y wget curl git gcc make zlib-devel bzip2-devel openssl-devel ncurses-devel sqlite-devel readline-devel tk-devel libffi-devel xz jq >/dev/null 2>&1
    elif [ -f /etc/debian_version ]; then
      apt-get update >/dev/null 2>&1
      apt-get install -y wget curl git gcc make zlib1g-dev build-essential libssl-dev zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev wget curl llvm libncurses5-dev libncursesw5-dev xz-utils tk-dev libffi-dev liblzma-dev jq >/dev/null 2>&1
    fi
    export DEPS_INSTALLED=true
  fi
}

# =========================================================
# 新增功能: 日志管理系统
# =========================================================
log_manager() {
    while true; do
        # 统计日志数量
        local log_count=$(ls -1 ${LOG_DIR}/${LOG_PREFIX}*.log 2>/dev/null | wc -l)
        local total_size=$(du -shc ${LOG_DIR}/${LOG_PREFIX}*.log 2>/dev/null | grep total | awk '{print $1}')
        [ -z "$total_size" ] && total_size="0K"

        echo -e "\n${CYAN}------- 日志管理系统 -------${NC}"
        echo -e "存储位置: ${LOG_DIR}"
        echo -e "日志统计: 共 ${GREEN}${log_count}${NC} 个文件, 占用 ${GREEN}${total_size}${NC}"
        echo -e "${CYAN}----------------------------${NC}"
        echo "1. 查看最新日志 (less)"
        echo "2. 列出所有日志"
        echo "3. 清理历史日志 (保留当前)"
        echo "4. 返回主菜单"
        echo -e "${CYAN}----------------------------${NC}"
        read -p "请选择: " log_choice

        case $log_choice in
            1)
                latest_log=$(ls -t ${LOG_DIR}/${LOG_PREFIX}*.log 2>/dev/null | head -n 1)
                if [ -f "$latest_log" ]; then
                    echo -e "${YELLOW}正在打开 $latest_log (按 q 退出查看)...${NC}"
                    sleep 1
                    less "$latest_log"
                else
                    echo -e "${RED}未找到日志文件${NC}"
                fi
                ;;
            2)
                echo -e "\n${BLUE}=== 日志列表 (按时间倒序) ===${NC}"
                ls -lh ${LOG_DIR}/${LOG_PREFIX}*.log 2>/dev/null | awk '{print $9, "(" $5 ")"}'
                echo -e "${BLUE}==============================${NC}"
                read -p "按回车继续..."
                ;;
            3)
                # 排除当前正在写入的日志文件
                logs_to_delete=$(ls ${LOG_DIR}/${LOG_PREFIX}*.log 2>/dev/null | grep -v "$CURRENT_LOG_NAME")
                
                if [ -z "$logs_to_delete" ]; then
                    echo -e "${YELLOW}没有可清理的历史日志 (仅有当前运行日志)${NC}"
                else
                    count=$(echo "$logs_to_delete" | wc -l)
                    echo -e "${RED}即将删除 $count 个历史日志文件!${NC}"
                    read -p "确认执行? [y/N]: " confirm
                    if [[ "$confirm" =~ ^[Yy]$ ]]; then
                        echo "$logs_to_delete" | xargs rm -f
                        echo -e "${GREEN}清理完成!${NC}"
                    else
                        echo "操作已取消"
                    fi
                fi
                ;;
            4) return ;;
            *) echo -e "${RED}无效输入${NC}" ;;
        esac
    done
}

# =========================================================
# 安装逻辑 (Python/Go/Node)
# =========================================================

install_python() {
  echo -e "\n${YELLOW}=== 安装 Python ===${NC}"
  check_disk_space 800 || return
  
  MIRROR_URL="https://npmmirror.com/mirrors/python/"
  raw_versions=$(curl $CURL_OPTS "$MIRROR_URL" | grep -oP 'href="3\.\d+\.\d+/"' | cut -d'"' -f2 | sed 's/\///g' | sort -V | tail -n 5)
  latest_ver=$(echo "$raw_versions" | tail -n 1)
  [ -z "$latest_ver" ] && latest_ver="3.11.8"
  
  echo -e "可选: \n$(echo "$raw_versions" | awk '{print " - " $0}')"
  read -p "输入版本 (默认: $latest_ver): " py_version
  [ -z "$py_version" ] && py_version="$latest_ver"

  if [ "$CUR_PY" == "$py_version" ]; then
    read -p "版本已存在，重装? [y/N]: " confirm; [[ ! $confirm =~ ^[Yy]$ ]] && return
  fi

  cd /tmp
  download_file "${MIRROR_URL}${py_version}/Python-${py_version}.tgz" || return
  
  echo -e "${BLUE}编译安装中 (请耐心等待)...${NC}"
  tar -zxvf "Python-${py_version}.tgz" >/dev/null || { echo -e "${RED}解压失败${NC}"; return 1; }
  cd "Python-${py_version}" || return 1
  
  ./configure --enable-optimizations --prefix=/usr/local/python3 >/dev/null || return 1
  make -j$(nproc) >/dev/null || { echo -e "${RED}make 失败${NC}"; return 1; }
  make install >/dev/null || { echo -e "${RED}install 失败${NC}"; return 1; }

  ln -sf /usr/local/python3/bin/python3 /usr/bin/python3
  ln -sf /usr/local/python3/bin/pip3 /usr/bin/pip3
  
  source /etc/profile 2>/dev/null || true; hash -r
  
  if ! python3 --version | grep -q "$py_version"; then echo -e "${RED}验证失败${NC}"; return 1; fi
  
  mkdir -p ~/.pip
  echo -e "[global]\nindex-url = https://mirrors.aliyun.com/pypi/simple/" > ~/.pip/pip.conf
  
  echo -e "${GREEN}Python $py_version 安装成功!${NC}"
  cd /tmp && rm -rf "Python-${py_version}.tgz" "Python-${py_version}"
}

install_golang() {
  echo -e "\n${YELLOW}=== 安装 Golang ===${NC}"
  check_disk_space 300 || return

  json_data=$(curl $CURL_OPTS "https://golang.google.cn/dl/?mode=json")
  if [ -n "$json_data" ]; then
    raw_versions=$(echo "$json_data" | jq -r '.[0:3] | .[].version' | sed 's/go//g')
    latest_ver=$(echo "$raw_versions" | head -n 1)
    echo -e "官方推荐: \n$(echo "$raw_versions" | awk '{print " - " $0}')"
  else
    latest_ver="1.21.6"
  fi

  read -p "输入版本 (默认: $latest_ver): " go_version
  [ -z "$go_version" ] && go_version="$latest_ver"
  go_version=${go_version#v}; go_version=${go_version#go}

  if [ "$CUR_GO" == "$go_version" ]; then
     read -p "版本已存在，重装? [y/N]: " confirm; [[ ! $confirm =~ ^[Yy]$ ]] && return
  fi

  cd /tmp
  download_file "https://mirrors.aliyun.com/golang/go${go_version}.linux-${GO_ARCH}.tar.gz" || return

  rm -rf /usr/local/go
  tar -C /usr/local -xzf "go${go_version}.linux-${GO_ARCH}.tar.gz" || return 1

  if ! grep -q "/usr/local/go/bin" /etc/profile; then
    echo 'export PATH=$PATH:/usr/local/go/bin' >> /etc/profile
    echo 'export GOPATH=$HOME/go' >> /etc/profile
    echo 'export PATH=$PATH:$GOPATH/bin' >> /etc/profile
  fi
  export PATH=$PATH:/usr/local/go/bin
  
  if ! go version | grep -q "go$go_version"; then echo -e "${RED}验证失败${NC}"; return 1; fi
  go env -w GOPROXY=https://goproxy.cn,direct
  
  echo -e "${GREEN}Golang $go_version 安装成功!${NC}"
  cd /tmp && rm -f "go${go_version}.linux-${GO_ARCH}.tar.gz"
}

install_nodejs() {
  echo -e "\n${YELLOW}=== 安装 Node.js ===${NC}"
  check_disk_space 200 || return

  json_data=$(curl $CURL_OPTS https://npmmirror.com/mirrors/node/index.json)
  if [ -n "$json_data" ]; then
    lts_ver=$(echo "$json_data" | jq -r 'map(select(.lts != false)) | .[0].version')
    curr_ver=$(echo "$json_data" | jq -r '.[0].version')
    echo -e "推荐: LTS=${GREEN}$lts_ver${NC}, 最新=${YELLOW}$curr_ver${NC}"
    default_ver=$lts_ver
  else
    default_ver="v18.19.0"
  fi

  read -p "输入版本 (默认: $default_ver): " node_version
  [ -z "$node_version" ] && node_version="$default_ver"
  if [[ $node_version != v* ]]; then v_node_version="v$node_version"; else v_node_version="$node_version"; fi

  if [ "$CUR_NODE" == "$v_node_version" ]; then
     read -p "版本已存在，重装? [y/N]: " confirm; [[ ! $confirm =~ ^[Yy]$ ]] && return
  fi

  cd /tmp
  download_file "https://npmmirror.com/mirrors/node/${v_node_version}/node-${v_node_version}-linux-${NODE_ARCH}.tar.xz" || return

  INSTALL_DIR="/usr/local/node"
  rm -rf $INSTALL_DIR; mkdir -p $INSTALL_DIR
  tar -xJf "node-${v_node_version}-linux-${NODE_ARCH}.tar.xz" -C $INSTALL_DIR --strip-components=1 || return 1

  ln -sf $INSTALL_DIR/bin/node /usr/bin/node
  ln -sf $INSTALL_DIR/bin/npm /usr/bin/npm
  ln -sf $INSTALL_DIR/bin/npx /usr/bin/npx
  ln -sf $INSTALL_DIR/bin/corepack /usr/bin/corepack

  hash -r
  if ! node -v | grep -q "$v_node_version"; then echo -e "${RED}验证失败${NC}"; return 1; fi

  $INSTALL_DIR/bin/npm config set registry https://registry.npmmirror.com
  echo -e "${GREEN}Node.js $v_node_version 安装成功!${NC}"
  cd /tmp && rm -f "node-${v_node_version}-linux-${NODE_ARCH}.tar.xz"
}

# =========================================================
# 主程序
# =========================================================
install_deps

while true; do
  check_current_versions

  echo -e "\n${BLUE}========================================${NC}"
  echo -e "   Linux 开发环境一键安装 V4.0 (运维版)"
  echo -e "   日志: ${CYAN}$LOG_FILE${NC}"
  echo -e "${BLUE}========================================${NC}"
  
  printf " 1. 安装 Python  [当前: %s]\n" "$MSG_PY"
  printf " 2. 安装 Golang  [当前: %s]\n" "$MSG_GO"
  printf " 3. 安装 Node.js [当前: %s]\n" "$MSG_NODE"
  echo   " 4. 日志管理系统 (查看/清理)"
  echo   " 5. 退出"
  echo -e "${BLUE}========================================${NC}"
  read -p "请输入选项 [1-5]: " choice

  case $choice in
    1) install_python ;;
    2) install_golang ;;
    3) install_nodejs ;;
    4) log_manager ;;
    5) echo "退出脚本"; exit 0 ;;
    *) echo -e "${RED}无效输入${NC}" ;;
  esac
done

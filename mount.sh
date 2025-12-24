#!/bin/bash

# ==========================================
# Linux 通用硬盘挂载脚本 V5 (修复颜色解析Bug)
# ==========================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}错误: 请使用 sudo 运行此脚本。${NC}"
   exit 1
fi

echo -e "${BLUE}=== 正在扫描系统中的块设备 ===${NC}"
echo ""

echo -e "设备列表:"
echo "--------------------------------------------------------------------------------"
printf "%-15s %-10s %-10s %-10s %-25s\n" "设备名" "大小" "类型" "文件系统" "当前挂载点"
echo "--------------------------------------------------------------------------------"

lsblk -P -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT | while read -r line; do
    eval "$line"
    
    if [[ "$TYPE" == "rom" || "$TYPE" == "loop" ]]; then continue; fi
    
    # 检查是否为有子分区的父盘
    IS_PARENT_DISK=false
    if [[ "$TYPE" == "disk" ]]; then
        CHILD_COUNT=$(lsblk -n -o NAME "/dev/$NAME" 2>/dev/null | wc -l)
        if [ "$CHILD_COUNT" -gt 1 ]; then
            IS_PARENT_DISK=true
        fi
    fi
    
    if [[ -n "$MOUNTPOINT" ]]; then
        printf "${YELLOW}%-15s %-10s %-10s %-10s %-25s${NC}\n" "$NAME" "$SIZE" "$TYPE" "$FSTYPE" "$MOUNTPOINT"
    elif [[ "$IS_PARENT_DISK" == true ]]; then
        printf "${CYAN}%-15s %-10s %-10s %-10s %-25s${NC}\n" "$NAME" "$SIZE" "$TYPE" "(物理父盘)" "(勿操作)"
    elif [[ -n "$FSTYPE" ]]; then
        printf "${GREEN}%-15s %-10s %-10s %-10s %-25s${NC}\n" "$NAME" "$SIZE" "$TYPE" "$FSTYPE" "(未挂载)"
    else
        printf "${WHITE}%-15s %-10s %-10s %-10s %-25s${NC}\n" "$NAME" "$SIZE" "$TYPE" "(未格式化)" ""
    fi
done
echo "--------------------------------------------------------------------------------"
echo -e "${GREEN}绿色${NC}: 建议挂载 | ${YELLOW}黄色${NC}: 已挂载 | ${WHITE}白色${NC}: 需格式化 | ${CYAN}青色${NC}: 物理父盘(勿动)"
echo ""

echo -e "${YELLOW}请输入要操作的设备名称 (例如: sdb 或 sdb1):${NC}"
read -r TARGET_DEV_NAME
if [[ "$TARGET_DEV_NAME" != /dev/* ]]; then TARGET_DEV="/dev/$TARGET_DEV_NAME"; else TARGET_DEV="$TARGET_DEV_NAME"; fi

if [ ! -b "$TARGET_DEV" ]; then
    echo -e "${RED}错误: 设备 $TARGET_DEV 不存在!${NC}"
    exit 1
fi

# ===========================
#  格式化检测与处理
# ===========================
DEV_FSTYPE=$(lsblk -no FSTYPE "$TARGET_DEV")

if [ -z "$DEV_FSTYPE" ]; then
    echo ""
    echo -e "${WHITE}警告: 检测到设备 $TARGET_DEV 尚未格式化 (无文件系统)。${NC}"
    
    HAS_CHILDREN=$(lsblk -n --output NAME "$TARGET_DEV" | wc -l)
    if [ "$HAS_CHILDREN" -gt 1 ]; then
        echo -e "${RED}严重警告: 设备 $TARGET_DEV 似乎包含分区 (例如 ${TARGET_DEV_NAME}1)。${NC}"
        echo -e "${RED}通常你应该挂载它的子分区，而不是整个磁盘！${NC}"
        echo -e "${RED}格式化整个磁盘将清除所有分区表！${NC}"
    fi

    echo -e "${RED}注意: 格式化将 清除 该设备上的所有数据！${NC}"
    echo "请选择文件系统格式:"
    echo " 1) ext4 (推荐，兼容性好)"
    echo " 2) xfs  (适合大文件)"
    echo " 3) 取消操作"
    read -p "请输入选项 [1-3]: " FORMAT_CHOICE

    case "$FORMAT_CHOICE" in
        1)
            echo "正在将 $TARGET_DEV 格式化为 ext4 ..."
            mkfs.ext4 -F "$TARGET_DEV"
            if [ $? -ne 0 ]; then echo -e "${RED}格式化失败!${NC}"; exit 1; fi
            DEV_FSTYPE="ext4"
            echo -e "${GREEN}格式化完成。${NC}"
            ;;
        2)
            if ! command -v mkfs.xfs &> /dev/null; then
                echo -e "${RED}错误: 未找到 xfs 工具 (xfsprogs)。请选择 ext4 或先安装工具。${NC}"
                exit 1
            fi
            echo "正在将 $TARGET_DEV 格式化为 xfs ..."
            mkfs.xfs -f "$TARGET_DEV"
            if [ $? -ne 0 ]; then echo -e "${RED}格式化失败!${NC}"; exit 1; fi
            DEV_FSTYPE="xfs"
            echo -e "${GREEN}格式化完成。${NC}"
            ;;
        *)
            echo "操作已取消。"
            exit 1
            ;;
    esac
fi

# ===========================
#  处理已挂载设备
# ===========================
CURRENT_MOUNT=$(lsblk -no MOUNTPOINT "$TARGET_DEV" | head -n 1)

if [ -n "$CURRENT_MOUNT" ]; then
    echo ""
    echo -e "${YELLOW}检测到设备 $TARGET_DEV 当前已挂载于: $CURRENT_MOUNT${NC}"
    echo -e "你需要先卸载它，才能挂载到新位置。"
    read -p "是否立即卸载并继续? [y/N]: " CONFIRM_UMOUNT
    
    if [[ "$CONFIRM_UMOUNT" =~ ^[Yy]$ ]]; then
        echo "正在卸载 $TARGET_DEV ..."
        lsblk -rn -o MOUNTPOINT "$TARGET_DEV" | grep -v "^$" | while read -r mp; do
             umount "$mp" 2>/dev/null
        done
        umount "$TARGET_DEV" 2>/dev/null 
        
        if [ -n "$(lsblk -no MOUNTPOINT "$TARGET_DEV")" ]; then
             echo -e "${RED}卸载失败! 设备正被使用。请手动停止相关进程后重试。${NC}"
             exit 1
        fi
        echo -e "${GREEN}卸载成功。${NC}"
    else
        echo "操作取消。"
        exit 0
    fi
fi

echo ""
echo -e "${YELLOW}请输入新的挂载点路径 (例如: /mnt/data):${NC}"
read -r MOUNT_POINT
[ -z "$MOUNT_POINT" ] && exit 1

if [ ! -d "$MOUNT_POINT" ]; then
    mkdir -p "$MOUNT_POINT"
    echo "创建目录: $MOUNT_POINT"
fi

echo "正在挂载 $TARGET_DEV ($DEV_FSTYPE) 到 $MOUNT_POINT ..."
mount "$TARGET_DEV" "$MOUNT_POINT"

if [ $? -ne 0 ]; then
    echo -e "${RED}挂载失败!${NC}"
    exit 1
fi

# ===========================
#  配置 Fstab
# ===========================
echo ""
read -p "是否更新开机自动挂载 (/etc/fstab)? [y/N]: " ENABLE_BOOT

if [[ "$ENABLE_BOOT" =~ ^[Yy]$ ]]; then
    UUID=$(blkid -s UUID -o value "$TARGET_DEV")
    if [ -z "$UUID" ]; then
        partprobe "$TARGET_DEV" 2>/dev/null
        sleep 1
        UUID=$(blkid -s UUID -o value "$TARGET_DEV")
    fi

    if [ -z "$UUID" ]; then
         echo -e "${RED}获取 UUID 失败，跳过 fstab 更新。${NC}"
    else
        cp /etc/fstab /etc/fstab.bak.$(date +%s)
        echo "已备份 /etc/fstab"
        
        if grep -q "$UUID" /etc/fstab; then
            sed -i "s|^UUID=$UUID|# [Modified] UUID=$UUID|g" /etc/fstab
        fi
        
        if [ -n "$CURRENT_MOUNT" ]; then
            ESC_OLD_MOUNT=$(echo "$CURRENT_MOUNT" | sed 's/\//\\\//g')
            sed -i "/^[^#].*[[:space:]]${ESC_OLD_MOUNT}[[:space:]]/s/^/# [Modified Old Path] /" /etc/fstab
        fi

        echo "UUID=$UUID $MOUNT_POINT $DEV_FSTYPE defaults 0 0" >> /etc/fstab
        
        echo "正在刷新 Systemd 缓存..."
        systemctl daemon-reload
        
        echo "正在验证 fstab..."
        mount -a
        if [ $? -eq 0 ]; then
             echo -e "${GREEN}/etc/fstab 更新完成且验证通过。${NC}"
        else
             echo -e "${RED}警告: fstab 验证失败! 请检查文件。${NC}"
        fi
    fi
fi

echo -e "${BLUE}=== 完成 ===${NC}"
lsblk -o NAME,FSTYPE,SIZE,MOUNTPOINT | grep "$(basename "$TARGET_DEV")"

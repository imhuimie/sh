#!/bin/bash

# ==========================================
# Linux 通用硬盘挂载脚本 V6 (智能识别分区结构)
# ==========================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'   # 新增：青色用于显示父磁盘
WHITE='\033[1;37m'  # 高亮白色用于未格式化
NC='\033[0m'

if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}错误: 请使用 sudo 运行此脚本。${NC}"
   exit 1
fi

echo -e "${BLUE}=== 正在扫描系统中的块设备 ===${NC}"
echo ""

# 列出设备
echo -e "设备列表:"
echo "--------------------------------------------------------------------------------"
printf "%-15s %-10s %-10s %-10s %-25s\n" "设备名" "大小" "类型" "文件系统" "当前状态/挂载点"
echo "--------------------------------------------------------------------------------"

lsblk -P -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT | while read -r line; do
    eval "$line"
    
    # 过滤掉 loop 和 rom
    if [[ "$TYPE" == "rom" || "$TYPE" == "loop" ]]; then continue; fi
    
    # 逻辑判断
    if [[ -n "$MOUNTPOINT" ]]; then
        # 黄色：已挂载
        printf "${YELLOW}%-15s %-10s %-10s %-10s %-25s${NC}\n" "$NAME" "$SIZE" "$TYPE" "$FSTYPE" "$MOUNTPOINT"
        
    elif [[ -n "$FSTYPE" ]]; then
        # 绿色：有文件系统但未挂载
        printf "${GREEN}%-15s %-10s %-10s %-10s %-25s${NC}\n" "$NAME" "$SIZE" "$TYPE" "$FSTYPE" "(未挂载)"
        
    else
        # 关键修改：检查是否为“父磁盘” (即包含子分区的 disk)
        IS_PARENT=0
        if [[ "$TYPE" == "disk" ]]; then
            # 检查该设备下是否有子节点
            # lsblk 列出该设备及其依赖，如果行数 > 1 说明有分区
            CHILD_COUNT=$(lsblk -n --list --output NAME "$NAME" | wc -l)
            if [ "$CHILD_COUNT" -gt 1 ]; then IS_PARENT=1; fi
        fi

        if [[ "$IS_PARENT" -eq 1 ]]; then
            # 青色：父磁盘 (包含分区，不建议直接操作)
            printf "${CYAN}%-15s %-10s %-10s %-10s %-25s${NC}\n" "$NAME" "$SIZE" "$TYPE" "(分区表)" "(含分区-请操作子设备)"
        else
            # 白色：真正的空盘 (无分区且无文件系统)
            printf "${WHITE}%-15s %-10s %-10s %-10s %-25s${NC}\n" "$NAME" "$SIZE" "$TYPE" "(未格式化)" "(建议挂载)"
        fi
    fi
done
echo "--------------------------------------------------------------------------------"
echo -e "${GREEN}绿色${NC}: 可挂载 | ${YELLOW}黄色${NC}: 已挂载 | ${WHITE}白色${NC}: 空盘(需格式化) | ${CYAN}青色${NC}: 物理父盘(勿动)"
echo ""

# 交互输入
echo -e "${YELLOW}请输入要操作的设备名称 (例如: sdb 或 sdb1):${NC}"
read -r TARGET_DEV_NAME
if [[ "$TARGET_DEV_NAME" != /dev/* ]]; then TARGET_DEV="/dev/$TARGET_DEV_NAME"; fi

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
    
    # 二次安全检查：如果用户强行输入了 sda (父磁盘)
    HAS_CHILDREN=$(lsblk -n --output NAME "$TARGET_DEV" | wc -l)
    if [ "$HAS_CHILDREN" -gt 1 ]; then
        echo -e "${RED}=======================================================${NC}"
        echo -e "${RED}危险警告! 你选择了 $TARGET_DEV，这是一个包含分区的物理磁盘。${NC}"
        echo -e "${RED}它下面似乎已经有分区了 (如 ${TARGET_DEV_NAME}1)。${NC}"
        echo -e "${RED}如果你继续格式化 $TARGET_DEV，所有分区和数据都将丢失！${NC}"
        echo -e "${RED}=======================================================${NC}"
        read -p "你确定要毁灭所有分区并格式化整块磁盘吗? (输入 YES 确认): " DIE_CONFIRM
        if [ "$DIE_CONFIRM" != "YES" ]; then
            echo "操作已终止。请重新运行脚本并选择子分区 (例如 ${TARGET_DEV_NAME}1)。"
            exit 1
        fi
    fi

    echo -e "${WHITE}警告: 设备 $TARGET_DEV 尚未格式化。${NC}"
    echo -e "${RED}注意: 格式化将 清除 数据！${NC}"
    echo "请选择文件系统:"
    echo " 1) ext4 (推荐)"
    echo " 2) xfs"
    echo " 3) 取消"
    read -p "选项 [1-3]: " FORMAT_CHOICE

    case "$FORMAT_CHOICE" in
        1)
            echo "格式化为 ext4 ..."
            mkfs.ext4 -F "$TARGET_DEV" || exit 1
            DEV_FSTYPE="ext4"
            ;;
        2)
            if ! command -v mkfs.xfs &> /dev/null; then echo "未找到 mkfs.xfs"; exit 1; fi
            echo "格式化为 xfs ..."
            mkfs.xfs -f "$TARGET_DEV" || exit 1
            DEV_FSTYPE="xfs"
            ;;
        *) exit 1 ;;
    esac
fi

# ===========================
#  处理已挂载 (同前)
# ===========================
CURRENT_MOUNT=$(lsblk -no MOUNTPOINT "$TARGET_DEV" | head -n 1)

if [ -n "$CURRENT_MOUNT" ]; then
    echo -e "${YELLOW}设备已挂载于: $CURRENT_MOUNT${NC}"
    read -p "是否卸载并重挂? [y/N]: " CONFIRM_UMOUNT
    if [[ "$CONFIRM_UMOUNT" =~ ^[Yy]$ ]]; then
        lsblk -rn -o MOUNTPOINT "$TARGET_DEV" | grep -v "^$" | while read -r mp; do umount "$mp"; done
        umount "$TARGET_DEV" 2>/dev/null
    else
        exit 0
    fi
fi

# 挂载逻辑
echo ""
echo -e "${YELLOW}请输入新挂载点 (例: /mnt/data):${NC}"
read -r MOUNT_POINT
[ -z "$MOUNT_POINT" ] && exit 1
[ ! -d "$MOUNT_POINT" ] && mkdir -p "$MOUNT_POINT"

mount "$TARGET_DEV" "$MOUNT_POINT" || { echo -e "${RED}挂载失败${NC}"; exit 1; }

# Fstab
echo ""
read -p "更新 /etc/fstab? [y/N]: " ENABLE_BOOT
if [[ "$ENABLE_BOOT" =~ ^[Yy]$ ]]; then
    UUID=$(blkid -s UUID -o value "$TARGET_DEV")
    [ -z "$UUID" ] && partprobe "$TARGET_DEV" && sleep 1 && UUID=$(blkid -s UUID -o value "$TARGET_DEV")
    
    if [ -n "$UUID" ]; then
        cp /etc/fstab /etc/fstab.bak.$(date +%s)
        # 移除旧记录
        if grep -q "$UUID" /etc/fstab; then sed -i "s|^UUID=$UUID|# &|g" /etc/fstab; fi
        if [ -n "$CURRENT_MOUNT" ]; then 
            ESC=$(echo "$CURRENT_MOUNT" | sed 's/\//\\\//g')
            sed -i "/^[^#].*[[:space:]]${ESC}[[:space:]]/s/^/# /" /etc/fstab
        fi
        
        echo "UUID=$UUID $MOUNT_POINT $DEV_FSTYPE defaults 0 0" >> /etc/fstab
        systemctl daemon-reload
        mount -a
        echo -e "${GREEN}fstab 更新完毕。${NC}"
    fi
fi

echo -e "${BLUE}=== 完成 ===${NC}"
lsblk -o NAME,FSTYPE,MOUNTPOINT | grep "$(basename "$TARGET_DEV")"

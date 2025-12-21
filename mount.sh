#!/bin/bash

# ==========================================
# Linux 通用硬盘挂载脚本 V3 (修复重挂载与Systemd刷新)
# ==========================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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
printf "%-15s %-10s %-10s %-10s %-25s\n" "设备名" "大小" "类型" "文件系统" "当前挂载点"
echo "--------------------------------------------------------------------------------"

lsblk -rno NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT | while read -r name size type fstype mountpoint; do
    if [[ "$type" == "rom" || "$type" == "loop" ]]; then continue; fi
    
    if [[ -z "$mountpoint" && -n "$fstype" ]]; then
        printf "${GREEN}%-15s %-10s %-10s %-10s %-25s${NC}\n" "$name" "$size" "$type" "$fstype" "(未挂载)"
    elif [[ -n "$mountpoint" ]]; then
        printf "${YELLOW}%-15s %-10s %-10s %-10s %-25s${NC}\n" "$name" "$size" "$type" "$fstype" "$mountpoint"
    else
        printf "%-15s %-10s %-10s %-10s %-25s\n" "$name" "$size" "$type" "$fstype" ""
    fi
done
echo "--------------------------------------------------------------------------------"
echo -e "${GREEN}绿色${NC}: 建议挂载 | ${YELLOW}黄色${NC}: 已挂载(支持重新挂载)"
echo ""

# 交互输入
echo -e "${YELLOW}请输入要挂载的设备名称 (例如: sdb1):${NC}"
read -r TARGET_DEV
if [[ "$TARGET_DEV" != /dev/* ]]; then TARGET_DEV="/dev/$TARGET_DEV"; fi

if [ ! -b "$TARGET_DEV" ]; then
    echo -e "${RED}错误: 设备 $TARGET_DEV 不存在!${NC}"
    exit 1
fi

DEV_FSTYPE=$(lsblk -no FSTYPE "$TARGET_DEV")
if [ -z "$DEV_FSTYPE" ]; then
    echo -e "${RED}错误: 设备未格式化，无法挂载。${NC}"
    exit 1
fi

# ===========================
#  处理已挂载设备
# ===========================
CURRENT_MOUNT=$(lsblk -no MOUNTPOINT "$TARGET_DEV")
# 注意：lsblk可能返回多行，如果挂载了多次，这里只取第一行或全部处理需要小心
# 为了简单起见，我们检测是否非空

if [ -n "$CURRENT_MOUNT" ]; then
    echo ""
    echo -e "${YELLOW}检测到设备 $TARGET_DEV 当前已挂载于: $CURRENT_MOUNT${NC}"
    echo -e "你需要先卸载它，才能挂载到新位置。"
    read -p "是否立即卸载并继续? [y/N]: " CONFIRM_UMOUNT
    
    if [[ "$CONFIRM_UMOUNT" =~ ^[Yy]$ ]]; then
        echo "正在卸载 $TARGET_DEV (及其所有挂载点)..."
        # 使用 umount -A 尝试卸载该设备的所有挂载点 (如果支持)，或者循环卸载
        for mpoint in $CURRENT_MOUNT; do
            umount "$mpoint" 2>/dev/null
            if [ $? -eq 0 ]; then
                echo "已卸载: $mpoint"
            else
                umount "$TARGET_DEV" 2>/dev/null 
            fi
        done
        
        # 再次检查
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

# 输入新挂载点
echo ""
echo -e "${YELLOW}请输入新的挂载点路径 (例如: /mnt/data):${NC}"
read -r MOUNT_POINT
[ -z "$MOUNT_POINT" ] && exit 1

if [ ! -d "$MOUNT_POINT" ]; then
    mkdir -p "$MOUNT_POINT"
    echo "创建目录: $MOUNT_POINT"
fi

# 执行挂载
echo "正在挂载 $TARGET_DEV 到 $MOUNT_POINT ..."
mount "$TARGET_DEV" "$MOUNT_POINT"

if [ $? -ne 0 ]; then
    echo -e "${RED}挂载失败!${NC}"
    exit 1
fi

# 配置 Fstab
echo ""
read -p "是否更新开机自动挂载 (/etc/fstab)? [y/N]: " ENABLE_BOOT

if [[ "$ENABLE_BOOT" =~ ^[Yy]$ ]]; then
    UUID=$(blkid -s UUID -o value "$TARGET_DEV")
    if [ -z "$UUID" ]; then
        echo "错误: 无法获取 UUID。"
    else
        cp /etc/fstab /etc/fstab.bak.$(date +%s)
        echo "已备份 /etc/fstab"
        
        # 1. 清理旧记录 (增强版)
        # 不仅匹配 UUID，如果旧挂载点存在，也注释掉包含旧挂载点的行
        if grep -q "$UUID" /etc/fstab; then
            sed -i "s|^UUID=$UUID|# [Modified] UUID=$UUID|g" /etc/fstab
            echo "注释掉旧的 UUID 记录..."
        fi
        
        # 如果刚才有旧挂载点，尝试根据路径清理 (防止 fstab 使用的是设备名而非UUID的情况)
        if [ -n "$CURRENT_MOUNT" ]; then
            # 转义斜杠以用于 sed
            ESC_OLD_MOUNT=$(echo "$CURRENT_MOUNT" | sed 's/\//\\\//g')
            # 只有当行没有被注释(#开头) 且 包含旧挂载点时才注释
            sed -i "/^[^#].*[[:space:]]${ESC_OLD_MOUNT}[[:space:]]/s/^/# [Modified Old Path] /" /etc/fstab
        fi

        # 2. 写入新记录
        echo "UUID=$UUID $MOUNT_POINT $DEV_FSTYPE defaults 0 0" >> /etc/fstab
        
        # 3. 关键修复：刷新 Systemd
        echo "正在刷新 Systemd 缓存 (systemctl daemon-reload)..."
        systemctl daemon-reload
        
        echo "正在验证 fstab..."
        mount -a
        if [ $? -eq 0 ]; then
             echo -e "${GREEN}/etc/fstab 更新完成且验证通过。${NC}"
        else
             echo -e "${RED}警告: fstab 验证失败! 请检查文件。${NC}"
             # 并不自动还原，因为可能只是小错误，让用户看提示更好
        fi
    fi
fi

echo -e "${BLUE}=== 完成 ===${NC}"
lsblk -o NAME,FSTYPE,MOUNTPOINT | grep "$TARGET_DEV"

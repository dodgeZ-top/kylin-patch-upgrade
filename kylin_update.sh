#!/bin/bash

# ============================================================
# 银河麒麟系统补丁升级脚本 (Kylin Patch Upgrade Script)
# ------------------------------------------------------------
# 作者: DodgeZ
# QQ: 3300151809
# 邮箱：z_dodge@163.com
# 版本: v1.0
# 日期: 2025-09-05
# ------------------------------------------------------------
# 脚本功能:
# - 自动检测当前目录下的 CNNVD 补丁包
# - 自动解压补丁包、生成本地 YUM 仓库
# - 执行系统升级并恢复原有 YUM 配置
# - 输出升级后的主要包版本
# ------------------------------------------------------------
# 版权声明:
# 本脚本仅供学习与交流使用，使用风险由使用者自行承担。
# ============================================================

set -euo pipefail

# -----------------------------
# 脚本目录与日志
# -----------------------------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

LOG_DIR="$HOME/kylin_patch_logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/kylin_patch_$(date +%F_%H%M%S).log"

exec > >(tee -a "$LOG_FILE") 2>&1

trap 'echo "脚本退出，日志保留在 $LOG_FILE"' EXIT
trap 'echo "错误发生在第 $LINENO 行: 命令 [$BASH_COMMAND]"; exit 1' ERR

echo "升级开始时间: $(date)"
echo "当前内核版本:"
nkvers || echo "nkvers 命令未找到或出错"

# -----------------------------
# 自动检测可用补丁包（文件名中包含 CNNVD）
# -----------------------------
echo "检测当前目录下可用补丁包..."
shopt -s nullglob
PATCH_TARS=( "$SCRIPT_DIR"/*CNNVD*.tar.gz )
shopt -u nullglob

if [ ${#PATCH_TARS[@]} -eq 0 ]; then
    echo "未找到任何包含 CNNVD 的补丁包，退出"
    exit 1
fi

echo "发现以下补丁包："
for i in "${!PATCH_TARS[@]}"; do
    echo "$i) $(basename "${PATCH_TARS[$i]}")"
done

read -rp "请输入要升级的补丁包序号: " CHOICE
PATCH_TAR="${PATCH_TARS[$CHOICE]}"
PATCH_DIR="${PATCH_TAR%.tar.gz}"

# -----------------------------
# 解压补丁包
# -----------------------------
echo "解压补丁包 $PATCH_TAR..."
if [ ! -d "$PATCH_DIR" ]; then
    tar -xf "$PATCH_TAR" -C "$SCRIPT_DIR"
fi

# -----------------------------
# 生成本地 yum 仓库
# -----------------------------
cd "$PATCH_DIR"
createrepo .

# -----------------------------
# 备份原有 repo
# -----------------------------
YUM_REPO="/etc/yum.repos.d/local_sp3.repo"
BACKUP_DIR="/etc/yum.repos.d/bak_$(date +%F_%H%M%S)"
mkdir -p "$BACKUP_DIR"
echo "备份所有旧 repo 到 $BACKUP_DIR"
shopt -s nullglob
REPO_FILES=(/etc/yum.repos.d/*.repo)
if [ ${#REPO_FILES[@]} -gt 0 ]; then
    mv /etc/yum.repos.d/*.repo "$BACKUP_DIR"/
fi
shopt -u nullglob

# 创建新的本地 repo
echo "生成本地 repo 文件..."
cat > "$YUM_REPO" << EOF
[local-sp3]
name=Local SP3 Patch Repository
baseurl=file://$PATCH_DIR
enabled=1
gpgcheck=0
EOF

# -----------------------------
# 清理缓存并升级
# -----------------------------
echo "清理 yum 缓存并更新..."
yum clean all
yum makecache

echo "开始升级..."
yum update -y || echo "yum update 出现错误，检查日志"

# -----------------------------
# 恢复原有 repo
# -----------------------------
echo "升级成功，恢复原有 repo..."
rm -f "$YUM_REPO"
if [ -d "$BACKUP_DIR" ]; then
    mv "$BACKUP_DIR"/* /etc/yum.repos.d/ || true
    rmdir "$BACKUP_DIR"
fi

# -----------------------------
# 输出升级后的主要包版本（只显示已安装）
# -----------------------------
echo "升级后的主要包版本:"
RPM_FILES=( $(find "$PATCH_DIR" -type f -name '*.rpm') )

if [ ${#RPM_FILES[@]} -gt 0 ]; then
    mapfile -t PATCH_PKGS < <(
        for f in "${RPM_FILES[@]}"; do
            basename "$f" | sed -E 's/-[0-9].*//'
        done | sort -u
    )
    for pkg in "${PATCH_PKGS[@]}"; do
        rpm -q "$pkg" &>/dev/null && rpm -q "$pkg"
    done
else
    echo "未找到任何 rpm 文件，跳过版本检查"
fi

echo "升级结束时间: $(date)"
echo "日志保存为 $LOG_FILE"

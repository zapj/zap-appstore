#!/bin/bash
# PostgreSQL 卸载脚本（zap appstore 调用）
# 依赖环境变量（由 zapexec 注入）：APPS_DIR APP_VERSION MAJOR_VERSION
set -euo pipefail

INSTALL_DIR="${APPS_DIR}/postgresql-${MAJOR_VERSION:-${APP_VERSION}}"

# ── 停止并禁用服务 ─────────────────────────────────────────
echo "stop postgresql service"
systemctl stop postgresql.service 2>/dev/null || true
systemctl disable postgresql.service 2>/dev/null || true
echo "wait postgresql stop"
sleep 3

# ── 备份数据 ───────────────────────────────────────────────
BAK_DIR="/root/zap_bak/postgresql"
mkdir -p "${BAK_DIR}"
if [ -d "${INSTALL_DIR}/data" ]; then
    cp -Rf "${INSTALL_DIR}/data" "${BAK_DIR}/postgresql.$(date +%Y%m%d%H%M%S)"
fi

# ── 删除安装目录（zap 侧随后清理 APP_PATH 元数据目录） ─────
if [ -d "${INSTALL_DIR}" ]; then
    echo "Removing ${INSTALL_DIR}..."
    rm -rf "${INSTALL_DIR}"
    echo "Removing done."
fi

# ── 移除服务文件 ───────────────────────────────────────────
rm -f /etc/systemd/system/postgresql.service
systemctl daemon-reload 2>/dev/null || true

echo "postgresql uninstall successful"

#!/bin/bash
# MariaDB 卸载脚本（zap appstore 调用）
# 依赖环境变量（由 zapexec 注入）：APPS_DIR APP_VERSION ZAP_PATH ZAPCTL
set -euo pipefail

INSTALL_DIR="${APPS_DIR}/mariadb-${APP_VERSION}"

# ── 停止并禁用服务 ─────────────────────────────────────────
echo "stop mariadb service"
if command -v systemctl >/dev/null 2>&1; then
    systemctl stop mariadb.service 2>/dev/null || true
    systemctl disable mariadb.service 2>/dev/null || true
else
    service mariadb stop 2>/dev/null || true
    chkconfig --del mariadb 2>/dev/null || true
fi
echo "wait mariadb stop"
sleep 3

# ── 备份数据与配置 ─────────────────────────────────────────
BAK_DIR="/root/zap_bak/mariadb"
mkdir -p "${BAK_DIR}"
if [ -d "${INSTALL_DIR}/data" ]; then
    cp -Rf "${INSTALL_DIR}/data" "${BAK_DIR}/mariadb.$(date +%Y%m%d%H%M%S)"
fi
if [ -d "/etc/mysql" ]; then
    cp -Rf /etc/mysql "${BAK_DIR}/mariadb.cnf.$(date +%Y%m%d%H%M%S)"
fi

# ── 移除软链与命令 ─────────────────────────────────────────
if [ -L "/usr/local/mariadb" ]; then
    rm -rf /usr/local/mariadb
fi
rm -f /usr/local/bin/mysql
rm -f /usr/local/bin/mysqldump
rm -f /usr/local/bin/mariadb-install-db

# ── 删除安装目录（zap 侧随后清理 APP_PATH 元数据目录） ─────
if [ -d "${INSTALL_DIR}" ]; then
    echo "Removing ${INSTALL_DIR}..."
    rm -rf "${INSTALL_DIR}"
    echo "Removing done."
fi

# ── 移除服务文件 ───────────────────────────────────────────
rm -f /etc/init.d/mariadb
rm -f /etc/systemd/system/mariadb.service
rm -f /etc/mysql/my.cnf
if command -v systemctl >/dev/null 2>&1; then
    systemctl daemon-reload 2>/dev/null || true
fi

echo "mariadb uninstall successful"

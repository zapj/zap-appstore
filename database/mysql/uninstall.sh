#!/bin/bash
# MySQL 卸载脚本（zap appstore 调用）
# 依赖环境变量（由 zapexec 注入）：APPS_DIR APP_VERSION
set -euo pipefail

INSTALL_DIR="${APPS_DIR}/mysql-${APP_VERSION}"

# ── 停止并禁用服务 ─────────────────────────────────────────
echo "stop mysql service"
if command -v systemctl >/dev/null 2>&1; then
    systemctl stop mysql.service 2>/dev/null || true
    systemctl disable mysql.service 2>/dev/null || true
elif command -v service >/dev/null 2>&1; then
    service mysql stop 2>/dev/null || true
    chkconfig --del mysql 2>/dev/null || true
fi
echo "wait mysql stop"
sleep 3

# ── 备份数据与配置 ─────────────────────────────────────────
BAK_DIR="/root/zap_bak/mysql"
mkdir -p "${BAK_DIR}"
if [ -d "${INSTALL_DIR}/data" ]; then
    cp -Rf "${INSTALL_DIR}/data" "${BAK_DIR}/mysql.$(date +%Y%m%d%H%M%S)"
fi
if [ -d "/etc/mysql" ]; then
    cp -Rf /etc/mysql "${BAK_DIR}/mysql.cnf.$(date +%Y%m%d%H%M%S)"
fi

# ── 移除软链与命令 ─────────────────────────────────────────
if [ -L "/usr/local/mysql" ]; then
    rm -rf /usr/local/mysql
fi
rm -f /usr/local/bin/mysql
rm -f /usr/local/bin/mysqldump
rm -f /usr/local/bin/myisamchk
rm -f /usr/local/bin/mysqld_safe
rm -f /usr/local/bin/mysqlcheck

# ── 删除安装目录（zap 侧随后清理 APP_PATH 元数据目录） ─────
if [ -d "${INSTALL_DIR}" ]; then
    echo "Removing ${INSTALL_DIR}..."
    rm -rf "${INSTALL_DIR}"
    echo "Removing done."
fi

# ── 移除服务文件 ───────────────────────────────────────────
rm -f /etc/init.d/mysql
rm -f /etc/init.d/mysqld
rm -f /etc/systemd/system/mysql.service
rm -f /etc/systemd/system/mysqld.service
if command -v systemctl >/dev/null 2>&1; then
    systemctl daemon-reload 2>/dev/null || true
fi

echo "mysql uninstall successful"

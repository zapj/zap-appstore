#!/bin/bash
# MySQL / MariaDB 合并卸载脚本（zap appstore 调用，按版本家族自动分流）
# 兼容两种安装目录命名：mysql-8.0 / mariadb-10.11（短版本）与
# mysql-8.0.46 / mariadb-10.11.19（早期完整版本）。
# 两家安装均以 mysql.service 为服务单元，配置同为 /etc/mysql/my.cnf，
# 凭据共用 mysql 凭据域（root / zapadm）。
# 依赖环境变量（由 zapexec 注入）：APPS_DIR APP_VERSION MAJOR_VERSION MINOR_VERSION APP_FAMILY ZAPCTL
# 可选选项：BACKUP_DATA（app.yaml options.uninstall，true=备份后删除，false=直接删除）
set -euo pipefail

# 家族以 zapexec 按 version_meta 下发的 APP_FAMILY 为准；
# 仅当未注入（旧版 zapexec 或 meta 缺失）时回退到按主版本号猜测并告警，保证卸载仍可进行。
if [ -n "${APP_FAMILY:-}" ]; then
    FAMILY="${APP_FAMILY}"
else
    case "${MAJOR_VERSION:-}" in
        10|11|12) FAMILY="mariadb" ;;
        *) FAMILY="mysql" ;;
    esac
    echo "[mysql-mariadb] warn: APP_FAMILY 未注入，按主版本号回退猜测 family=${FAMILY}（建议升级 zapexec 以 version_meta 为准）"
fi

SHORT_VERSION="${MAJOR_VERSION}.${MINOR_VERSION}"
INSTALL_DIR="${APPS_DIR}/${FAMILY}-${SHORT_VERSION}"
# 兼容早期按完整版本命名的安装目录
if [ ! -d "${INSTALL_DIR}" ]; then
    LEGACY_DIR="${APPS_DIR}/${FAMILY}-${APP_VERSION}"
    if [ -d "${LEGACY_DIR}" ]; then
        INSTALL_DIR="${LEGACY_DIR}"
    fi
fi

# ── 停止并禁用服务 ─────────────────────────────────────────
echo "stop ${FAMILY} service"
if command -v systemctl >/dev/null 2>&1; then
    systemctl stop mysql.service 2>/dev/null || true
    systemctl disable mysql.service 2>/dev/null || true
    systemctl stop mariadb.service 2>/dev/null || true
    systemctl disable mariadb.service 2>/dev/null || true
elif command -v service >/dev/null 2>&1; then
    service mysql stop 2>/dev/null || true
    service mariadb stop 2>/dev/null || true
    chkconfig --del mysql 2>/dev/null || true
    chkconfig --del mariadb 2>/dev/null || true
fi
sleep 3

# ── 备份数据与配置（BACKUP_DATA=false 时跳过，直接删除） ────
if [ "${BACKUP_DATA:-true}" = "true" ]; then
    BAK_DIR="/root/zap_bak/${FAMILY}"
    mkdir -p "${BAK_DIR}"
    if [ -d "${INSTALL_DIR}/data" ]; then
        cp -Rf "${INSTALL_DIR}/data" "${BAK_DIR}/${FAMILY}.$(date +%Y%m%d%H%M%S)"
    fi
    if [ -d "/etc/mysql" ]; then
        cp -Rf /etc/mysql "${BAK_DIR}/${FAMILY}.cnf.$(date +%Y%m%d%H%M%S)"
    fi
else
    echo "skip data/config backup (BACKUP_DATA=false)"
fi

# ── 移除软链与命令 ─────────────────────────────────────────
if [ -L "/usr/local/mysql" ]; then
    rm -rf /usr/local/mysql
fi
if [ -L "/usr/local/mariadb" ]; then
    rm -rf /usr/local/mariadb
fi
rm -f /usr/local/bin/mysql /usr/local/bin/mysqldump /usr/local/bin/myisamchk \
      /usr/local/bin/mysqld_safe /usr/local/bin/mysqlcheck /usr/local/bin/mariadb \
      /usr/local/bin/mariadb-install-db

# ── 删除安装目录（zap 侧随后清理 APP_PATH 元数据目录） ─────
if [ -n "${INSTALL_DIR}" ] && [ -d "${INSTALL_DIR}" ]; then
    echo "Removing ${INSTALL_DIR}..."
    rm -rf "${INSTALL_DIR}"
fi

# ── 移除服务与配置文件 ─────────────────────────────────────
rm -f /etc/init.d/mysql /etc/init.d/mariadb
rm -f /etc/systemd/system/mysql.service /etc/systemd/system/mariadb.service
rm -f /etc/mysql/my.cnf
if command -v systemctl >/dev/null 2>&1; then
    systemctl daemon-reload 2>/dev/null || true
fi

# ── 清理加密凭据（两家共用 mysql 凭据域） ───────────────────
echo "remove ${FAMILY} credentials"
"${ZAPCTL:-/usr/local/bin/zapctl}" cred rm mysql root 2>/dev/null || true
"${ZAPCTL:-/usr/local/bin/zapctl}" cred rm mysql zapadm 2>/dev/null || true

echo "${FAMILY} uninstall successful"

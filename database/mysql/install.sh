#!/bin/bash
# MySQL / MariaDB 合并安装入口（zap appstore 调用）
# 家族由 zapexec 按 app.yaml version_meta 下发（APP_FAMILY=mysql|mariadb），脚本不自行
# 按版本号猜测：跨家族版本号可能重合（如 mysql 9 与 mariadb 9 并存），同版本号仅凭
# MAJOR_VERSION 无法区分。安装装错家族代价高，取不到家族直接报错，绝不猜测。
# 依赖环境变量（由 zapexec 注入）：ZAP_PATH APPS_DIR PKG_PATH APP_PATH APP_VERSION MAJOR_VERSION APP_FAMILY
set -euo pipefail

case "${APP_FAMILY:-}" in
    mysql)   FAMILY="mysql" ;;
    mariadb) FAMILY="mariadb" ;;
    *)
        echo "[mysql-mariadb] 无法确定安装家族: APP_FAMILY=${APP_FAMILY:-空} APP_VERSION=${APP_VERSION:-unknown}"
        echo "[mysql-mariadb] 请检查 app.yaml version_meta 中是否声明了该版本的 family"
        exit 1
        ;;
esac

echo "[mysql-mariadb] family=${FAMILY} version=${APP_VERSION:-unknown} install.sh -> ${FAMILY}-install.sh"
exec bash "${BASH_SOURCE[0]%/*}/${FAMILY}-install.sh"

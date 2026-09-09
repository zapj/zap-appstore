#!/bin/bash
# MySQL / MariaDB 合并安装入口（zap appstore 调用）
# 按所选版本的家族自动分流：MariaDB 版本主版本号 >= 10（10 / 11 / 12 系），
# 其余（8 / 9 系）为 MySQL。与 app.yaml version_meta 保持同一规则。
# 依赖环境变量（由 zapexec 注入）：ZAP_PATH APPS_DIR PKG_PATH APP_PATH APP_VERSION MAJOR_VERSION
set -euo pipefail

case "${MAJOR_VERSION:-}" in
    10|11|12) FAMILY="mariadb" ;;
    *) FAMILY="mysql" ;;
esac

echo "[mysql-mariadb] family=${FAMILY} version=${APP_VERSION:-unknown} install.sh auto-routing"
exec bash "${BASH_SOURCE[0]%/*}/install-${FAMILY}.sh"

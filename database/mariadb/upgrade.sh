#!/bin/bash
# MariaDB 升级脚本（zap appstore 调用）
# 依赖环境变量（由 zapexec 注入）：PKG_PATH（包源目录） APP_VERSION APP_OLD_VERSION
# 升级策略：先执行新版本包自带的卸载脚本，再执行安装脚本
set -euo pipefail

echo "mariadb upgrade: ${APP_OLD_VERSION:-?} -> ${APP_VERSION:-?}"

# 调用新版本源目录中的卸载/安装脚本（zap 已注入新版本环境变量）
if [ -f "${PKG_PATH}/uninstall.sh" ]; then
    bash "${PKG_PATH}/uninstall.sh" || true
fi
if [ -f "${PKG_PATH}/install.sh" ]; then
    bash "${PKG_PATH}/install.sh"
fi

echo "mariadb upgrade successful"

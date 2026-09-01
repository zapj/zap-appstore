#!/bin/bash
# PHP 卸载脚本（zap appstore 调用）
# 依赖环境变量（由 zapexec 注入）：APPS_DIR APP_VERSION MAJOR_VERSION MINOR_VERSION
set -euo pipefail

PHP_SHORT_VERSION="${MAJOR_VERSION}.${MINOR_VERSION}"
PHP_INSTALL_PATH="${APPS_DIR}/php-${PHP_SHORT_VERSION}"
SERVICE_NAME="php-fpm-${PHP_SHORT_VERSION}"

echo "uninstall PHP ${APP_VERSION}"

# ── 停止并移除服务 ─────────────────────────────────────────
if command -v systemctl >/dev/null 2>&1; then
    systemctl stop "${SERVICE_NAME}.service" 2>/dev/null || true
    systemctl disable "${SERVICE_NAME}.service" 2>/dev/null || true
    rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
    systemctl daemon-reload 2>/dev/null || true
fi
if command -v chkconfig >/dev/null 2>&1; then
    chkconfig --del "${SERVICE_NAME}" 2>/dev/null || true
    rm -f "/etc/init.d/${SERVICE_NAME}"
fi

# ── 移除全局命令链接 ───────────────────────────────────────
rm -f /usr/local/bin/php
rm -f /usr/local/bin/php-cgi
rm -f /usr/local/bin/pear
rm -f /usr/local/bin/pecl
if [ -L /usr/bin/php ]; then
    rm -f /usr/bin/php
fi

# ── 删除安装目录（zap 侧随后清理 APP_PATH 元数据目录） ─────
if [ -d "${PHP_INSTALL_PATH}" ]; then
    echo "Removing ${PHP_INSTALL_PATH}..."
    rm -rf "${PHP_INSTALL_PATH}"
    echo "Removing done."
fi

echo "php uninstall successful"

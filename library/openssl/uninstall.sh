#!/bin/bash
# OpenSSL 库卸载脚本(zap appstore 调用)
# 依赖环境变量(由 zapexec 注入):APPS_DIR MAJOR_VERSION MINOR_VERSION
set -euo pipefail

SHORT_VERSION="${MAJOR_VERSION}.${MINOR_VERSION}"
INSTALL_PATH="${APPS_DIR}/openssl${SHORT_VERSION}"

echo "uninstall openssl ${SHORT_VERSION}"

# ── ld.so 索引片段(按 major 分文件,不影响其它 major 实例) ────────────────
rm -f "/etc/ld.so.conf.d/zap-openssl-${MAJOR_VERSION}.conf"
ldconfig >/dev/null 2>&1 || true

if [ -d "${INSTALL_PATH}" ]; then
    rm -rf "${INSTALL_PATH}"
fi

echo "openssl uninstall successful"

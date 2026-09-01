#!/bin/bash
# PCRE2 库卸载脚本（zap appstore 调用）
# 依赖环境变量（由 zapexec 注入）：APPS_DIR MAJOR_VERSION MINOR_VERSION
set -euo pipefail

S_VERSION="${MAJOR_VERSION}${MINOR_VERSION}"
INSTALL_PATH="${APPS_DIR}/libpcre2${S_VERSION}"

echo "uninstall libpcre2"
rm -f /usr/local/lib/pkgconfig/libpcre2-8.pc
if [ -d "${INSTALL_PATH}" ]; then
    rm -rf "${INSTALL_PATH}"
fi
echo "libpcre2 uninstall successful"

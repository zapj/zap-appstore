#!/bin/bash
# OpenSSL 库卸载脚本（zap appstore 调用）
# 依赖环境变量（由 zapexec 注入）：APPS_DIR MAJOR_VERSION MINOR_VERSION
set -euo pipefail

SHORT_VERSION="${MAJOR_VERSION}.${MINOR_VERSION}"
INSTALL_PATH="${APPS_DIR}/openssl${SHORT_VERSION}"

echo "uninstall openssl"
rm -f /usr/local/lib/pkgconfig/libssl.pc
rm -f /usr/local/lib/pkgconfig/libcrypto.pc
rm -f /usr/local/lib/pkgconfig/openssl.pc
if [ -d "${INSTALL_PATH}" ]; then
    rm -rf "${INSTALL_PATH}"
fi
echo "openssl uninstall successful"

#!/bin/bash
# OpenSSL 库卸载脚本(zap appstore 调用)
# 依赖环境变量(由 zapexec 注入):APPS_DIR MAJOR_VERSION MINOR_VERSION
set -euo pipefail

SHORT_VERSION="${MAJOR_VERSION}.${MINOR_VERSION}"
INSTALL_PATH="${APPS_DIR}/openssl${SHORT_VERSION}"

echo "uninstall openssl ${SHORT_VERSION}"

# ── pkg-config 链接(仅当指向本安装时删除,不影响其它共存实例) ─────────────
for _pc in openssl.pc libssl.pc libcrypto.pc; do
    _f="/usr/local/lib/pkgconfig/${_pc}"
    if [ -L "${_f}" ] && [ "$(readlink "${_f}")" = "${INSTALL_PATH}/lib/pkgconfig/${_pc}" ]; then
        rm -f "${_f}"
    fi
done

# ── soname 兼容链接(仅当指向本安装时删除) ─────────────────────────────────
for _lib in libssl libcrypto; do
    _f="/usr/local/lib/${_lib}.so.${MAJOR_VERSION}"
    if [ -L "${_f}" ] && [ "$(readlink "${_f}")" = "${INSTALL_PATH}/lib/${_lib}.so" ]; then
        rm -f "${_f}"
    fi
done

# ── ld.so 索引片段(按 major 分文件,不影响其它 major 实例) ────────────────
rm -f "/etc/ld.so.conf.d/zap-openssl-${MAJOR_VERSION}.conf"
ldconfig >/dev/null 2>&1 || true

if [ -d "${INSTALL_PATH}" ]; then
    rm -rf "${INSTALL_PATH}"
fi
echo "openssl uninstall successful"

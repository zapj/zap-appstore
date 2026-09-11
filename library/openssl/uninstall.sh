#!/bin/bash
# OpenSSL 库卸载脚本(zap appstore 调用)
# 依赖环境变量(由 zapexec 注入):APPS_DIR MAJOR_VERSION MINOR_VERSION
set -euo pipefail



#从APP_OLD_VERSION 解析旧版本，获取 MAJOR_VERSION MINOR_VERSION
OLD_MAJOR_VERSION=$(version_major "${APP_OLD_VERSION}")
OLD_MINOR_VERSION=$(version_minor "${APP_OLD_VERSION}")
SHORT_VERSION="${OLD_MAJOR_VERSION}.${OLD_MINOR_VERSION}"
INSTALL_DIR="${APPS_DIR}/openssl${SHORT_VERSION}"

INFO_FILE="${APP_PATH}/info.yaml"
INSTALL_DIR="$(resolve_install_dir "${INFO_FILE}" "${LINK_DIR}")"


echo "uninstall openssl ${SHORT_VERSION}  ${INSTALL_DIR}"

# ── ld.so 索引片段(按 major 分文件,不影响其它 major 实例) ────────────────
rm -f "/etc/ld.so.conf.d/zap-openssl-${OLD_MAJOR_VERSION}.conf"
ldconfig >/dev/null 2>&1 || true

# 删除前的安全校验：必须位于 APPS_DIR 之下且是其直接子目录
assert_under_apps_dir "${INSTALL_DIR}" "${APPS_DIR}" || exit 1
if [ "$(dirname "${INSTALL_DIR}")" != "${APPS_DIR}" ]; then
    log_error "安装目录不在 ${APPS_DIR} 下，无法卸载"
    exit 1
fi

if [ -d "${INSTALL_DIR}" ]; then
    rm -rf "${INSTALL_DIR}"
fi

echo "openssl uninstall successful"

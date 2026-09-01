#!/bin/bash
# OpenSSL 库安装脚本（zap appstore 调用，源码编译）
# 依赖环境变量（由 zapexec 注入）：ZAP_PATH ZAPCTL APPS_DIR PKG_PATH APP_ID APP_VERSION MAJOR_VERSION MINOR_VERSION BUILD_PATH CPU_NUM
set -euo pipefail

source "${ZAP_PATH}/scripts/zap/bash_utils.sh"

cd "${PKG_PATH}"
SHORT_VERSION="${MAJOR_VERSION}.${MINOR_VERSION}"
INSTALL_PATH="${APPS_DIR}/openssl${SHORT_VERSION}"

if [ -z "${APP_VERSION}" ]; then
    APP_VERSION="1.1.1w"
fi

if [ ! -f "openssl-${APP_VERSION}.tar.gz" ]; then
    wget -O "openssl-${APP_VERSION}.tar.gz" "https://mirrors.zap.cn/pkg/openssl/openssl-${APP_VERSION}.tar.gz"
fi

rm -rf "${BUILD_PATH}"
mkdir -p "${BUILD_PATH}"
tar zxf "openssl-${APP_VERSION}.tar.gz" -C "${BUILD_PATH}"
cd "${BUILD_PATH}/openssl-${APP_VERSION}"

./config -Wl,-rpath="${INSTALL_PATH}/lib" --prefix="${INSTALL_PATH}" --openssldir="${INSTALL_PATH}" -fPIC shared enable-weak-ssl-ciphers
make depend
make -j "${CPU_NUM:-1}" && make install

if [ ! -d "${INSTALL_PATH}" ]; then
    echo "openssl ${APP_VERSION} Install failed"
    exit 1
fi

mkdir -p /usr/local/lib/pkgconfig
ln -sf "${INSTALL_PATH}/lib/pkgconfig/openssl.pc" /usr/local/lib/pkgconfig/openssl.pc
ln -sf "${INSTALL_PATH}/lib/pkgconfig/libssl.pc" /usr/local/lib/pkgconfig/libssl.pc
ln -sf "${INSTALL_PATH}/lib/pkgconfig/libcrypto.pc" /usr/local/lib/pkgconfig/libcrypto.pc

# 提供系统库版本链接，供依赖旧版本号的程序加载
if [ "${SHORT_VERSION}" = "1.1" ] && [ ! -f "/usr/local/lib/libssl.so.1.1" ]; then
    ln -sf "${INSTALL_PATH}/lib/libssl.so" /usr/local/lib/libssl.so.1.1
    ln -sf "${INSTALL_PATH}/lib/libcrypto.so" /usr/local/lib/libcrypto.so.1.1
    ldconfig
fi
if [ "${MAJOR_VERSION}" = "3" ] && [ ! -f "/usr/local/lib/libssl.so.3" ]; then
    ln -sf "${INSTALL_PATH}/lib/libssl.so" /usr/local/lib/libssl.so.3
    ln -sf "${INSTALL_PATH}/lib/libcrypto.so" /usr/local/lib/libcrypto.so.3
    ldconfig
fi

if [ ! -d "${INSTALL_PATH}/ssl" ]; then
    mkdir -p "${INSTALL_PATH}/ssl"
    if [ -f "${INSTALL_PATH}/openssl.cnf" ]; then
        cp "${INSTALL_PATH}/openssl.cnf" "${INSTALL_PATH}/ssl/openssl.cnf"
    fi
fi

COLS_DATA="install_dir=${INSTALL_PATH},\
expose=none,\
status=active,\
app_status=stoped,\
instance=openssl${SHORT_VERSION},\
pid_file=none,\
config_file=${INSTALL_PATH}/lib/pkgconfig/openssl.pc"
${ZAPCTL} table apps -d "${COLS_DATA}" -w "id=${APP_ID}"
echo "openssl ${APP_VERSION} installing successful"

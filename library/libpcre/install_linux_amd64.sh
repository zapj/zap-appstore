#!/bin/bash
# PCRE 8.x 库安装脚本（zap appstore 调用，源码编译）
# 依赖环境变量（由 zapexec 注入）：ZAP_PATH ZAPCTL APPS_DIR PKG_PATH APP_ID APP_VERSION MAJOR_VERSION MINOR_VERSION BUILD_PATH CPU_NUM
set -euo pipefail

source "${ZAP_PATH}/scripts/zap/bash_utils.sh"

S_VERSION="${MAJOR_VERSION}${MINOR_VERSION}"
INSTALL_PATH="${APPS_DIR}/libpcre${S_VERSION}"

cd "${PKG_PATH}"
if [ ! -f "pcre-${APP_VERSION}.tar.gz" ]; then
    wget -O "pcre-${APP_VERSION}.tar.gz" "https://mirrors.zap.cn/pkg/libpcre/pcre-${APP_VERSION}.tar.gz"
fi

rm -rf "${BUILD_PATH}"
mkdir -p "${BUILD_PATH}"
tar zxf "pcre-${APP_VERSION}.tar.gz" -C "${BUILD_PATH}"
cd "${BUILD_PATH}/pcre-${APP_VERSION}"

./configure --prefix="${INSTALL_PATH}" --enable-utf8 --enable-unicode-properties
make -j "${CPU_NUM:-1}" && make install

if [ ! -d "${INSTALL_PATH}" ]; then
    echo "libpcre ${APP_VERSION} Install failed"
    exit 1
fi

mkdir -p /usr/local/lib/pkgconfig
ln -sf "${INSTALL_PATH}/lib/pkgconfig/libpcre.pc" /usr/local/lib/pkgconfig/libpcre.pc

COLS_DATA="install_dir=${INSTALL_PATH},\
expose=none,\
status=active,\
app_status=stoped,\
instance=libpcre${S_VERSION},\
pid_file=none,\
config_file=${INSTALL_PATH}/lib/pkgconfig/libpcre.pc"
${ZAPCTL} table apps -d "${COLS_DATA}" -w "id=${APP_ID}"
echo "libpcre ${APP_VERSION} installing successful"

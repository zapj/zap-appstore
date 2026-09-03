#!/bin/bash
# libpng 库安装脚本（zap appstore 调用，源码编译）
# 依赖环境变量（由 zapexec 注入）：ZAP_PATH APPS_DIR PKG_PATH APP_PATH APP_VERSION MAJOR_VERSION MINOR_VERSION BUILD_PATH CPU_NUM
set -euo pipefail

source "${ZAP_PATH}/scripts/zap/bash_utils.sh"

S_VERSION="${MAJOR_VERSION}${MINOR_VERSION}"
INSTALL_PATH="${APPS_DIR}/libpng${S_VERSION}"

if [ -z "${APP_VERSION}" ]; then
    APP_VERSION="1.6.37"
fi

cd "${PKG_PATH}"
if [ ! -f "libpng-${APP_VERSION}.tar.gz" ]; then
    wget -O "libpng-${APP_VERSION}.tar.gz" "https://mirrors.zap.cn/pkg/libpng/libpng-${APP_VERSION}.tar.gz"
fi

rm -rf "${BUILD_PATH}"
mkdir -p "${BUILD_PATH}"
tar zxf "libpng-${APP_VERSION}.tar.gz" -C "${BUILD_PATH}"
cd "${BUILD_PATH}/libpng-${APP_VERSION}"

./configure --prefix="${INSTALL_PATH}"
make -j "${CPU_NUM:-1}" && make install

if [ ! -d "${INSTALL_PATH}" ]; then
    echo "libpng ${APP_VERSION} Install failed"
    exit 1
fi

mkdir -p /usr/local/lib/pkgconfig
ln -sf "${INSTALL_PATH}/lib/pkgconfig/libpng.pc" /usr/local/lib/pkgconfig/libpng.pc
ln -sf "${INSTALL_PATH}/lib/pkgconfig/libpng16.pc" /usr/local/lib/pkgconfig/libpng16.pc

# ── 登记实例信息(apps/<category>/<name>/info.yaml,供「已安装」展示)──────
# 说明:运行元数据(version/run_id/installed_at...)由 zapexec 写入同目录
# meta.yaml;本应用为无守护进程的静态库,故不写 svc_name/pid_file
# (状态由 zapexec 返回 unknown)。
ensure_dir "${APP_PATH}"
cat > "${APP_PATH}/info.yaml" <<EOF
instance: libpng${S_VERSION}
install_dir: ${INSTALL_PATH}
config_file: ${INSTALL_PATH}/lib/pkgconfig/libpng.pc
expose: none
tags:
  - library
  - image
EOF
echo "libpng ${APP_VERSION} installing successful"

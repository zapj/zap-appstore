#!/bin/bash
# Nginx 编译安装脚本（zap appstore 调用）
# 依赖环境变量（由 zapexec 注入）：ZAP_PATH ZAPCTL APPS_DIR PKG_PATH APP_ID APP_VERSION BUILD_PATH CPU_NUM
set -euo pipefail

source "${ZAP_PATH}/scripts/zap/bash_utils.sh"

# ── 运行用户 www ───────────────────────────────────────────
if ! id www >/dev/null 2>&1; then
    useradd -r -s /sbin/nologin www
fi

preInstallation

ZLIB_VERSION="1.3.1"
ZLIB_PKG_URL="https://www.zlib.net/zlib-${ZLIB_VERSION}.tar.gz"
ZLIB_PKG_NAME="zlib-${ZLIB_VERSION}.tar.gz"
ZLIB_DIRNAME="zlib-${ZLIB_VERSION}"

NGINX_PKG_URL="https://nginx.org/download/nginx-${APP_VERSION}.tar.gz"
NGINX_PKG_NAME="nginx-${APP_VERSION}.tar.gz"
NGINX_DIRNAME="nginx-${APP_VERSION}"

PCRE2_VERSION="10.37"
PCRE2_PKG_URL="https://github.com/PCRE2Project/pcre2/releases/download/pcre2-${PCRE2_VERSION}/pcre2-${PCRE2_VERSION}.tar.gz"
PCRE2_PKG_NAME="pcre2-${PCRE2_VERSION}.tar.gz"
PCRE2_DIRNAME="pcre2-${PCRE2_VERSION}"

INSTALL_PATH="${APPS_DIR}/nginx-${APP_VERSION}"

cd "${PKG_PATH}"
# ── 下载依赖源码包 ─────────────────────────────────────────
if [ ! -f "${NGINX_PKG_NAME}" ]; then
    echo "Downloading nginx"
    wget -O "${NGINX_PKG_NAME}" "${NGINX_PKG_URL}"
fi
if [ ! -f "${ZLIB_PKG_NAME}" ]; then
    echo "Downloading zlib"
    wget -O "${ZLIB_PKG_NAME}" "${ZLIB_PKG_URL}"
fi
if [ ! -f "${PCRE2_PKG_NAME}" ]; then
    echo "Downloading pcre2"
    wget -O "${PCRE2_PKG_NAME}" "${PCRE2_PKG_URL}"
fi

# ── 解压 ───────────────────────────────────────────────────
echo "unpacking PKGs"
rm -rf "${BUILD_PATH}"
mkdir -p "${BUILD_PATH}"
tar -xzf "${ZLIB_PKG_NAME}" -C "${BUILD_PATH}"
tar -xzf "${NGINX_PKG_NAME}" -C "${BUILD_PATH}"
tar -xzf "${PCRE2_PKG_NAME}" -C "${BUILD_PATH}"

# ── 编译安装 ───────────────────────────────────────────────
echo "building nginx"
cd "${BUILD_PATH}/${NGINX_DIRNAME}"

./configure \
    --user=www \
    --group=www \
    --prefix="${INSTALL_PATH}" \
    --with-http_ssl_module \
    --with-http_v2_module \
    --with-http_auth_request_module \
    --with-stream \
    --with-stream_ssl_module \
    --with-stream_ssl_preread_module \
    --with-pcre2="${BUILD_PATH}/${PCRE2_DIRNAME}" \
    --with-zlib="${BUILD_PATH}/${ZLIB_DIRNAME}"

make -j "${CPU_NUM:-1}" && make install
echo "nginx build success"

# ── 配置 ───────────────────────────────────────────────────
echo "Generating dhparam"
openssl dhparam -out "${INSTALL_PATH}/conf/dhparam.pem" 2048

mkdir -p "${INSTALL_PATH}/conf/conf.d"
mkdir -p "${INSTALL_PATH}/conf/site-enabled"
mkdir -p /var/log/nginx

cp -rf "${ZAP_PATH}/scripts/zap/conf/nginx.conf" "${INSTALL_PATH}/conf/nginx.conf"
cp -rf "${ZAP_PATH}/scripts/zap/conf/default.conf" "${INSTALL_PATH}/conf/conf.d/default.conf"

# ── 软链与服务 ─────────────────────────────────────────────
echo "Setting up nginx symlink"
INSTANCE_NAME="${NGINX_DIRNAME}"
if [ ! -d "${APPS_DIR}/nginx" ]; then
    ln -s "${INSTALL_PATH}" "${APPS_DIR}/nginx"
    INSTANCE_NAME="nginx"
    echo "nginx symlink created"
fi

if command -v systemctl >/dev/null 2>&1; then
    if [ ! -f "/etc/systemd/system/nginx.service" ]; then
        cp "${ZAP_PATH}/scripts/systemd/nginx.service" /etc/systemd/system/nginx.service
    fi
    systemctl daemon-reload
    systemctl enable nginx.service
    systemctl start nginx.service
    sleep 1
    nginx_status=$(systemctl is-active nginx.service)
else
    service nginx start
    sleep 1
    nginx_status="active"
fi

echo "nginx installed to ${INSTALL_PATH}"

# ── 更新 zap 应用表 ────────────────────────────────────────
CHANGE_APPS_CONFIG="install_dir=${INSTALL_PATH},\
expose=http=80\nhttps=443,\
status=active,\
app_status=${nginx_status},\
instance=${INSTANCE_NAME},\
pid_file=/var/run/nginx.pid,\
config_file=${INSTALL_PATH}/conf/nginx.conf"

${ZAPCTL} table apps -d "${CHANGE_APPS_CONFIG}" -w "id=${APP_ID}"
echo "nginx config updated"
if [ "${nginx_status}" != "active" ]; then
    echo "Error start nginx.service failed"
fi
echo "nginx install successful"

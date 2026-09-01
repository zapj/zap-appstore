#!/bin/bash
# PHP 编译安装脚本（zap appstore 调用）
# 依赖环境变量（由 zapexec 注入）：ZAP_PATH ZAPCTL APPS_DIR PKG_PATH APP_ID APP_VERSION MAJOR_VERSION MINOR_VERSION BUILD_PATH CPU_NUM ZAP_DATA_PATH
#
# 版本兼容性提示：
#   PHP 7.0 要求 OpenSSL >= 0.9.8, < 1.2
#   PHP 7.1-8.0 要求 OpenSSL >= 1.0.1, < 3.0
#   PHP >= 8.1 要求 OpenSSL >= 1.0.2, < 4.0
set -euo pipefail

source "${ZAP_PATH}/scripts/zap/bash_utils.sh"

# ── 编译依赖 ───────────────────────────────────────────────
if command -v apt-get >/dev/null 2>&1; then
    apt-get update
    apt-get install -y \
        libxml2-dev libsqlite3-dev libcurl4-openssl-dev libjpeg-dev libwebp-dev \
        libpng-dev libonig-dev libicu-dev libzip-dev libpq-dev zlib1g-dev pkg-config || true
elif command -v yum >/dev/null 2>&1; then
    yum install -y libxml2-devel sqlite-devel curl-devel libjpeg-devel libwebp-devel \
        libpng-devel oniguruma-devel libicu-devel libzip-devel postgresql-devel zlib-devel pkgconfig || true
fi

# ── 运行用户 www（php-fpm 以 www 运行） ────────────────────
if ! id www >/dev/null 2>&1; then
    useradd -r -s /sbin/nologin www
fi

preInstallation

# ── 低版本 PHP 需要 openssl 1.1 ───────────────────────────
if [[ "${APP_VERSION}" < "8.1.0" ]]; then
    if [ ! -d "${APPS_DIR}/openssl1.1" ]; then
        echo "Please install openssl1.1 first"
        exit 1
    fi
    export PKG_CONFIG_PATH="${APPS_DIR}/openssl1.1/lib/pkgconfig"
fi
echo "PKG_CONFIG_PATH: ${PKG_CONFIG_PATH:-}"

PHP_VERSION="${APP_VERSION}"
PHP_SHORT_VERSION="${MAJOR_VERSION}.${MINOR_VERSION}"
PHP_DOWNLOAD_URL="https://cn2.php.net/distributions/php-${PHP_VERSION}.tar.gz"
PHP_DOWNLOAD_NAME="php-${PHP_VERSION}.tar.gz"
PHP_INSTALL_PATH="${APPS_DIR}/php-${PHP_SHORT_VERSION}"
PHP_FPM_SOCK="/var/run/php-fpm-${PHP_SHORT_VERSION}.sock"
PHP_FPM_PID="/var/run/php-fpm-${PHP_SHORT_VERSION}.pid"
PHP_FPM_ERROR_LOG="/var/log/php/php-${PHP_SHORT_VERSION}.log"

cd "${PKG_PATH}"
if [ ! -f "${PHP_DOWNLOAD_NAME}" ]; then
    echo "Downloading PHP"
    wget -c --progress=dot -e dotbytes=100k -O "${PHP_DOWNLOAD_NAME}" "${PHP_DOWNLOAD_URL}"
fi

echo "unpacking PKGs"
rm -rf "${BUILD_PATH}"
mkdir -p "${BUILD_PATH}"
tar -xzf "${PHP_DOWNLOAD_NAME}" -C "${BUILD_PATH}"

# ── 编译安装 ───────────────────────────────────────────────
echo "building PHP ${APP_VERSION}"
cd "${BUILD_PATH}/php-${APP_VERSION}"

# GD 相关选项随版本差异：PHP 7.x 用 --with-jpeg-dir，8.0 起用 --with-jpeg，8.1 起支持 --with-webp
GD_OPT="--enable-gd"
if [[ "${MAJOR_VERSION}" == "7" ]]; then
    GD_OPT="${GD_OPT} --with-jpeg-dir"
else
    GD_OPT="${GD_OPT} --with-jpeg"
    if [[ "${APP_VERSION}" > "8.1.0" ]]; then
        GD_OPT="${GD_OPT} --with-webp"
    fi
fi

./configure \
    --prefix="${PHP_INSTALL_PATH}" \
    --with-config-file-path="${PHP_INSTALL_PATH}/etc" \
    --with-config-file-scan-dir="${PHP_INSTALL_PATH}/etc/php.d" \
    --disable-rpath \
    --enable-sysvsem \
    --enable-sysvshm \
    --enable-pcntl \
    --enable-fpm \
    --with-fpm-user=www \
    --with-fpm-group=www \
    --with-openssl \
    --with-zlib \
    --with-zip \
    --enable-soap \
    --enable-sockets \
    --with-curl \
    ${GD_OPT} \
    --enable-mysqlnd \
    --with-mysqli=mysqlnd \
    --with-pdo-mysql=mysqlnd \
    --enable-mbstring \
    --enable-intl \
    --with-pear

echo "make install"
make -j "${CPU_NUM:-1}" && make install

if [ ! -d "${PHP_INSTALL_PATH}" ]; then
    echo "PHP ${APP_VERSION} Install failed"
    exit 1
fi

# ── 配置文件 ───────────────────────────────────────────────
mkdir -p "${PHP_INSTALL_PATH}/etc/php.d"
cp "${BUILD_PATH}/php-${APP_VERSION}/php.ini-production" "${PHP_INSTALL_PATH}/etc/php.ini"
if [ -f "${BUILD_PATH}/php-${APP_VERSION}/sapi/fpm/php-fpm.conf" ]; then
    cp "${BUILD_PATH}/php-${APP_VERSION}/sapi/fpm/php-fpm.conf" "${PHP_INSTALL_PATH}/etc/php-fpm.conf"
else
    cp "${PHP_INSTALL_PATH}/etc/php-fpm.conf.default" "${PHP_INSTALL_PATH}/etc/php-fpm.conf"
fi
if [ -f "${BUILD_PATH}/php-${APP_VERSION}/sapi/fpm/www.conf" ]; then
    cp "${BUILD_PATH}/php-${APP_VERSION}/sapi/fpm/www.conf" "${PHP_INSTALL_PATH}/etc/php-fpm.d/www.conf"
else
    cp "${PHP_INSTALL_PATH}/etc/php-fpm.d/www.conf.default" "${PHP_INSTALL_PATH}/etc/php-fpm.d/www.conf"
fi

mkdir -p /var/log/php
sed -i "s#;pid = run/php-fpm.pid#pid = ${PHP_FPM_PID}#g" "${PHP_INSTALL_PATH}/etc/php-fpm.conf"
sed -i "s#;error_log = log/php-fpm.log#error_log = ${PHP_FPM_ERROR_LOG}#g" "${PHP_INSTALL_PATH}/etc/php-fpm.conf"
sed -i "s#listen = 127.0.0.1:9000#listen = ${PHP_FPM_SOCK}#g" "${PHP_INSTALL_PATH}/etc/php-fpm.d/www.conf"
sed -i "s#;listen.mode = 0660#listen.mode = 0666#g" "${PHP_INSTALL_PATH}/etc/php-fpm.d/www.conf"

# ── systemd / init.d 服务 ─────────────────────────────────
if command -v systemctl >/dev/null 2>&1; then
    if [ -f "${BUILD_PATH}/php-${APP_VERSION}/sapi/fpm/php-fpm.service" ]; then
        cp "${BUILD_PATH}/php-${APP_VERSION}/sapi/fpm/php-fpm.service" "/etc/systemd/system/php-fpm-${PHP_SHORT_VERSION}.service"
    else
        # 生成最小服务单元（部分发行版源码不含 php-fpm.service）
        cat > "/etc/systemd/system/php-fpm-${PHP_SHORT_VERSION}.service" <<EOF
[Unit]
Description=The PHP FastCGI Process Manager (${PHP_SHORT_VERSION})
After=network.target

[Service]
Type=forking
ExecStart=${PHP_INSTALL_PATH}/sbin/php-fpm -y ${PHP_INSTALL_PATH}/etc/php-fpm.conf
ExecReload=/bin/kill -USR2 \\$MAINPID
PrivateTmp=false

[Install]
WantedBy=multi-user.target
EOF
    fi
    sed -i "s#^PrivateTmp=true#PrivateTmp=false#g" "/etc/systemd/system/php-fpm-${PHP_SHORT_VERSION}.service"
    systemctl daemon-reload
    systemctl enable "php-fpm-${PHP_SHORT_VERSION}.service"
    systemctl start "php-fpm-${PHP_SHORT_VERSION}.service"
elif command -v chkconfig >/dev/null 2>&1; then
    if [ -f "${BUILD_PATH}/php-${APP_VERSION}/sapi/fpm/init.d.php-fpm" ]; then
        cp "${BUILD_PATH}/php-${APP_VERSION}/sapi/fpm/init.d.php-fpm" "/etc/init.d/php-fpm-${PHP_SHORT_VERSION}"
        chmod +x "/etc/init.d/php-fpm-${PHP_SHORT_VERSION}"
    fi
    chkconfig --add "php-fpm-${PHP_SHORT_VERSION}"
    chkconfig "php-fpm-${PHP_SHORT_VERSION}" on
    service "php-fpm-${PHP_SHORT_VERSION}" start
fi

# ── 全局命令链接 ───────────────────────────────────────────
ln -sf "${PHP_INSTALL_PATH}/bin/php" /usr/local/bin/php
ln -sf "${PHP_INSTALL_PATH}/bin/php-cgi" /usr/local/bin/php-cgi
ln -sf "${PHP_INSTALL_PATH}/bin/pear" /usr/local/bin/pear
ln -sf "${PHP_INSTALL_PATH}/bin/pecl" /usr/local/bin/pecl
if [ ! -e /usr/bin/php ]; then
    ln -s "${PHP_INSTALL_PATH}/bin/php" /usr/bin/php
fi

# ── 更新 zap 应用表 ────────────────────────────────────────
COLS_DATA="install_dir=${PHP_INSTALL_PATH},\
expose=unix:${PHP_FPM_SOCK},\
status=active,\
app_status=stoped,\
instance=php${PHP_SHORT_VERSION},\
pid_file=${PHP_FPM_PID},\
config_file=${PHP_INSTALL_PATH}/etc/php.ini"

echo "update zap apps"
${ZAPCTL} table apps -d "${COLS_DATA}" -w "id=${APP_ID}"

echo "PHP ${APP_VERSION} installing successful"

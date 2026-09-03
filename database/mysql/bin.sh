#!/bin/bash
# MySQL 安装脚本（zap appstore 调用）
# 依赖环境变量（由 zapexec 注入）：ZAP_PATH APPS_DIR PKG_PATH APP_PATH APP_VERSION
set -euo pipefail

source "${ZAP_PATH}/scripts/zap/bash_utils.sh"

# ── 系统用户 ───────────────────────────────────────────────
if ! id mysql >/dev/null 2>&1; then
    groupadd mysql
    useradd -r -g mysql -s /bin/false mysql
fi

# ── 运行时依赖库 ───────────────────────────────────────────
if command -v apt-get >/dev/null 2>&1; then
    apt-get update
    apt-get install -y libncurses5 libaio1 libncurses6 || true
elif command -v yum >/dev/null 2>&1; then
    yum install -y libaio ncurses-compat-libs || true
fi

mkdir -p /var/log/mysql /var/run/mysqld
chown -R mysql:mysql /var/log/mysql /var/run/mysqld

# ── 选择与系统 glibc 匹配的官方二进制包 ───────────────────
# MySQL 5.7 仅提供 glibc2.12 的 tar.gz；8.0 提供 glibc2.17/2.28 的 tar.xz
if [[ "${APP_VERSION}" < "8.0.0" ]]; then
    PKG_TARBALL="mysql-${APP_VERSION}-linux-glibc2.12-x86_64.tar.gz"
    PKG_EXTRACT_DIR="mysql-${APP_VERSION}-linux-glibc2.12-x86_64"
else
    GLIBC_VERSION=$(getconf GNU_LIBC_VERSION 2>/dev/null | awk '{print $2}')
    GLIBC_VERSION="${GLIBC_VERSION:-2.17}"
    if [[ "${GLIBC_VERSION}" < "2.28" ]]; then
        GLIBC_VERSION="2.17"
    else
        GLIBC_VERSION="2.28"
    fi
    PKG_TARBALL="mysql-${APP_VERSION}-linux-glibc${GLIBC_VERSION}-x86_64.tar.xz"
    PKG_EXTRACT_DIR="mysql-${APP_VERSION}-linux-glibc${GLIBC_VERSION}-x86_64"
fi

cd "${PKG_PATH}"
if [ ! -f "${PKG_TARBALL}" ]; then
    if ! wget "https://mirrors.zap.cn/pkg/mysql/${PKG_TARBALL}" -O "${PKG_TARBALL}"; then
        echo "Error download mysql: ${PKG_TARBALL}"
        exit 1
    fi
fi
tar xf "${PKG_TARBALL}" -C "${APPS_DIR}"

# ── 安装目录（解压目录名含 glibc 标识，统一重命名为 mysql-版本） ──
INSTALL_DIR="${APPS_DIR}/mysql-${APP_VERSION}"
if [ -d "${APPS_DIR}/${PKG_EXTRACT_DIR}" ] && [ ! -d "${INSTALL_DIR}" ]; then
    mv "${APPS_DIR}/${PKG_EXTRACT_DIR}" "${INSTALL_DIR}"
fi
if [ ! -d "${INSTALL_DIR}" ]; then
    echo "Error unpacking mysql: ${INSTALL_DIR} not found"
    exit 1
fi

if [ ! -L /usr/local/mysql ] && [ ! -d /usr/local/mysql ]; then
    ln -s "${INSTALL_DIR}" /usr/local/mysql
fi

ln -sf "${INSTALL_DIR}/bin/mysql" /usr/local/bin/mysql
ln -sf "${INSTALL_DIR}/bin/mysqldump" /usr/local/bin/mysqldump
ln -sf "${INSTALL_DIR}/bin/myisamchk" /usr/local/bin/myisamchk
ln -sf "${INSTALL_DIR}/bin/mysqld_safe" /usr/local/bin/mysqld_safe
ln -sf "${INSTALL_DIR}/bin/mysqlcheck" /usr/local/bin/mysqlcheck

# ── 配置 ───────────────────────────────────────────────────
if [ -d "/etc/mysql" ]; then
    mv /etc/mysql "/etc/mysql.bak.$(date +%Y%m%d%H%M%S)"
fi
mkdir -p /etc/mysql

cd "${INSTALL_DIR}"
mkdir -p mysql-files
chmod 750 mysql-files
chown -R mysql:mysql "${INSTALL_DIR}"

# 初始化数据目录（无密码模式，随后设置 root 密码）
bin/mysqld --initialize-insecure --basedir=/usr/local/mysql --datadir=/usr/local/mysql/data --user=mysql

if [[ "${APP_VERSION}" > "8.0.0" ]]; then
    cp -Rf "${ZAP_PATH}/scripts/zap/conf/mysql_8.cnf" /etc/mysql/my.cnf
else
    cp -Rf "${ZAP_PATH}/scripts/zap/conf/mysql_57.cnf" /etc/mysql/my.cnf
fi

# ── 开机自启 ───────────────────────────────────────────────
cp support-files/mysql.server /etc/init.d/mysql
chmod +x /etc/init.d/mysql
if command -v systemctl >/dev/null 2>&1; then
    cp -f "${ZAP_PATH}/scripts/systemd/mysql.service" /etc/systemd/system/mysql.service
    systemctl daemon-reload
    systemctl enable mysql.service
    systemctl start mysql.service
elif command -v chkconfig >/dev/null 2>&1; then
    chkconfig --add mysql
    chkconfig mysql on
    service mysql start
fi

# ── 设置密码与 zap 管理账号 ────────────────────────────────
MYSQL_ROOT_PASSWORD=$(openssl rand -hex 8 2>/dev/null || true)
if [ -z "${MYSQL_ROOT_PASSWORD}" ]; then
    MYSQL_ROOT_PASSWORD=$(< /dev/urandom tr -dc A-Za-z0-9_ | head -c9)
fi

# 等待 mysqld 就绪（最多 60s）
for _ in $(seq 1 60); do
    if bin/mysqladmin -u root status >/dev/null 2>&1; then
        break
    fi
    sleep 1
done

if ! bin/mysqladmin -u root password "${MYSQL_ROOT_PASSWORD}"; then
    echo "Error setting root password"
else
    bin/mysql -u root --password="${MYSQL_ROOT_PASSWORD}" -e "CREATE USER 'zapadm'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';"
    bin/mysql -u root --password="${MYSQL_ROOT_PASSWORD}" -e "GRANT ALL PRIVILEGES ON *.* TO 'zapadm'@'localhost' WITH GRANT OPTION;"
    bin/mysql -u root --password="${MYSQL_ROOT_PASSWORD}" -e "FLUSH PRIVILEGES;"
fi

wzap_conf mysql_u "root"
wzap_conf mysql_p "${MYSQL_ROOT_PASSWORD}"
${ZAPCTL} config set mysql_u "zapadm"
${ZAPCTL} config set mysql_p "${MYSQL_ROOT_PASSWORD}"

# ── 登记实例信息(apps/<category>/<name>/info.yaml,供「已安装」展示)──────
# svc_name=mysql(systemd unit mysql.service),状态探测与面板启停走 systemctl;
# pid_file 保留,作为无 systemd 环境下的兜底探活依据。
ensure_dir "${APP_PATH}"
cat > "${APP_PATH}/info.yaml" <<EOF
svc_name: mysql
instance: mysql${APP_VERSION}
install_dir: ${INSTALL_DIR}
config_file: /etc/mysql/my.cnf
pid_file: /usr/local/mysql/data/mysql.pid
expose:
  - unix:/var/run/mysqld/mysqld.sock
  - tcp:127.0.0.1:3306
tags:
  - database
  - sql
EOF

echo "mysql install successful"

#!/bin/bash
# MariaDB 安装脚本（zap appstore 调用）
# 依赖环境变量（由 zapexec 注入）：ZAP_PATH APPS_DIR PKG_PATH APP_PATH APP_VERSION
set -euo pipefail

source "${ZAP_PATH}/scripts/zap/bash_utils.sh"

# ── 系统用户 ───────────────────────────────────────────────
if ! id mariadb >/dev/null 2>&1; then
    groupadd mariadb
    useradd -r -g mariadb -s /bin/false mariadb
fi

# ── 运行时依赖库 ───────────────────────────────────────────
if command -v apt-get >/dev/null 2>&1; then
    apt-get update
    apt-get install -y libncurses5 libaio1 libncurses6 || true
elif command -v yum >/dev/null 2>&1; then
    yum install -y libaio ncurses-compat-libs || true
fi

mkdir -p /var/log/mariadb /var/run/mariadb
chown -R mariadb:mariadb /var/log/mariadb /var/run/mariadb

# ── 解压二进制包 ───────────────────────────────────────────
PKG_TARBALL="mariadb-${APP_VERSION}-linux-systemd-x86_64.tar.gz"
cd "${PKG_PATH}"
if [ ! -f "${PKG_TARBALL}" ]; then
    if ! wget "https://mirrors.zap.cn/pkg/mariadb/${PKG_TARBALL}" -O "${PKG_TARBALL}"; then
        echo "Error download mariadb: ${PKG_TARBALL}"
        exit 1
    fi
fi
tar xf "${PKG_TARBALL}" -C "${APPS_DIR}"

INSTALL_DIR="${APPS_DIR}/mariadb-${APP_VERSION}"
if [ ! -d "${INSTALL_DIR}" ]; then
    mv "${APPS_DIR}/mariadb-${APP_VERSION}-linux-systemd-x86_64" "${INSTALL_DIR}"
fi

if [ ! -L /usr/local/mariadb ] && [ ! -d /usr/local/mariadb ]; then
    ln -s "${INSTALL_DIR}" /usr/local/mariadb
fi

ln -sf "${INSTALL_DIR}/bin/mysql" /usr/local/bin/mysql
ln -sf "${INSTALL_DIR}/bin/mysqldump" /usr/local/bin/mysqldump
ln -sf "${INSTALL_DIR}/bin/mariadb-install-db" /usr/local/bin/mariadb-install-db

# ── 配置 ───────────────────────────────────────────────────
mkdir -p /etc/mysql
cp -Rf "${ZAP_PATH}/scripts/zap/conf/mariadb.cnf" /etc/mysql/my.cnf

cd "${INSTALL_DIR}"
chown -R mariadb:mariadb "${INSTALL_DIR}"

# 初始化数据目录
${INSTALL_DIR}/scripts/mariadb-install-db --user=mariadb --datadir="${INSTALL_DIR}/data" --basedir="${INSTALL_DIR}"

# ── 开机自启 ───────────────────────────────────────────────
if command -v systemctl >/dev/null 2>&1; then
    cp -f "${ZAP_PATH}/scripts/systemd/mariadb.service" /etc/systemd/system/mariadb.service
    systemctl daemon-reload
    systemctl enable mariadb.service
    systemctl start mariadb.service
else
    cp support-files/mysql.server /etc/init.d/mariadb
    chmod +x /etc/init.d/mariadb
    chkconfig --add mariadb
    chkconfig mariadb on
    service mariadb start
fi

# ── 设置密码与 zap 管理账号 ────────────────────────────────
MYSQL_ROOT_PASSWORD=$(openssl rand -hex 8 2>/dev/null || true)
if [ -z "${MYSQL_ROOT_PASSWORD}" ]; then
    MYSQL_ROOT_PASSWORD=$(< /dev/urandom tr -dc A-Za-z0-9_ | head -c9)
fi

# 等待 mariadb 就绪（最多 60s）
for _ in $(seq 1 60); do
    if ${INSTALL_DIR}/bin/mysqladmin -u root status >/dev/null 2>&1; then
        break
    fi
    sleep 1
done

if ! ${INSTALL_DIR}/bin/mysqladmin -u root password "${MYSQL_ROOT_PASSWORD}"; then
    echo "Error setting root password"
else
    ${INSTALL_DIR}/bin/mysql -u root --password="${MYSQL_ROOT_PASSWORD}" -e "CREATE USER 'zapadm'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';"
    ${INSTALL_DIR}/bin/mysql -u root --password="${MYSQL_ROOT_PASSWORD}" -e "GRANT ALL PRIVILEGES ON *.* TO 'zapadm'@'localhost' WITH GRANT OPTION;"
    ${INSTALL_DIR}/bin/mysql -u root --password="${MYSQL_ROOT_PASSWORD}" -e "FLUSH PRIVILEGES;"
fi

wzap_conf mariadb_u "root"
wzap_conf mariadb_p "${MYSQL_ROOT_PASSWORD}"
${ZAPCTL} config set mariadb_u "zapadm"
${ZAPCTL} config set mariadb_p "${MYSQL_ROOT_PASSWORD}"

# ── 登记实例信息(apps/<category>/<name>/info.yaml,供「已安装」展示)──────
# svc_name=mariadb(systemd unit mariadb.service),状态探测与面板启停走
# systemctl;pid_file 保留,作为无 systemd 环境下的兜底探活依据。
ensure_dir "${APP_PATH}"
cat > "${APP_PATH}/info.yaml" <<EOF
svc_name: mariadb
instance: mariadb${APP_VERSION}
install_dir: ${INSTALL_DIR}
config_file: /etc/mysql/my.cnf
pid_file: ${INSTALL_DIR}/data/mariadb.pid
expose:
  - unix:/var/run/mariadb/mariadb.sock
  - tcp:127.0.0.1:3306
tags:
  - database
  - sql
EOF

echo "mariadb install successful"

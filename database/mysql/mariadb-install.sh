#!/bin/bash
# MariaDB 安装脚本（zap appstore 调用）
# 依赖环境变量（由 zapexec 注入）：ZAP_PATH APPS_DIR PKG_PATH APP_PATH APP_VERSION
set -euo pipefail

source "${ZAP_PATH}/scripts/zap/bash_utils.sh"


MYSQL_SHORT_VERSION="${MAJOR_VERSION}.${MINOR_VERSION}"
# check mysql is installed
if [ -d "/usr/local/mysql" ]; then
    log_error "mysql 已安装,请先卸载 mysql 后再安装 mariadb"
    exit 1
fi

# ── 系统用户 ───────────────────────────────────────────────
if ! id mysql >/dev/null 2>&1; then
    ensure_user mysql mysql
fi

# ── 运行时依赖库 ───────────────────────────────────────────
if command -v apt-get >/dev/null 2>&1; then
    apt-get update
    apt-get install -y libncurses5 libaio1 libncurses6 || true
elif command -v yum >/dev/null 2>&1; then
    yum install -y libaio libaio-devel numactl-libs numactl-devel || true
fi

mkdir -p /var/log/mysql /var/run/mysqld
chown -R mysql:mysql /var/log/mysql /var/run/mysqld

# ── 解压二进制包 ───────────────────────────────────────────
PKG_TARBALL="mariadb-${APP_VERSION}-linux-systemd-x86_64.tar.gz"
cd "${PKG_PATH}"
if [ ! -f "${PKG_TARBALL}" ]; then
    log_info "下载 mariadb: ${PKG_TARBALL}"
    # 统一走 bash_utils::download_file（curl --progress-bar / wget --show-progress）：
    # 非 TTY 下以 \r 原地刷新，日志里只占一行进度条，而非 wget 默认的逐行 dot 进度
    download_file "https://mirrors.zap.cn/pkg/mariadb/${PKG_TARBALL}" "${PKG_TARBALL}"
fi
tar xf "${PKG_TARBALL}" -C "${APPS_DIR}"

INSTALL_DIR="${APPS_DIR}/mariadb-${MYSQL_SHORT_VERSION}"
if [ ! -d "${INSTALL_DIR}" ]; then
    mv "${APPS_DIR}/mariadb-${APP_VERSION}-linux-systemd-x86_64" "${INSTALL_DIR}"
fi

if [ ! -L /usr/local/mysql ] && [ ! -d /usr/local/mysql ]; then
    ln -s "${INSTALL_DIR}" /usr/local/mysql
fi

ln -sf "${INSTALL_DIR}/bin/mariadb" /usr/local/bin/mariadb
ln -sf "${INSTALL_DIR}/bin/mysql" /usr/local/bin/mysql
ln -sf "${INSTALL_DIR}/bin/mysqldump" /usr/local/bin/mysqldump

# ── 配置 ───────────────────────────────────────────────────
if [ -d "/etc/mysql" ]; then
    mv /etc/mysql /etc/mysql.bak.$(date +%s)
fi
ensure_dir "/etc/mysql"

cat > /etc/mysql/my.cnf <<EOF
[client-server]
port            = 3306
socket          = /tmp/mysql.sock

[mysqld]
user            = mysql
basedir         = /usr/local/mysql
datadir         = /usr/local/mysql/data
tmpdir          = /tmp
pid-file        = /var/run/mysqld/mysql.pid

character-set-server  = utf8mb4
collation-server      = utf8mb4_general_ci


max_connections         = 500
connect_timeout         = 10
wait_timeout            = 28800
max_allowed_packet      = 16M


default_storage_engine  = InnoDB

# 建议设置为物理内存的 50% - 70%
innodb_buffer_pool_size = 1G
innodb_log_file_size    = 256M
innodb_flush_log_at_trx_commit = 1
innodb_file_per_table   = 1

# ---------- 日志配置 ----------
log_error               = /var/log/mysql/error.log

[client]
default-character-set   = utf8mb4
EOF

cd "${INSTALL_DIR}"
chown -R mysql:mysql "${INSTALL_DIR}"

# 初始化数据目录
${INSTALL_DIR}/scripts/mariadb-install-db --user=mysql --datadir="${INSTALL_DIR}/data" --basedir="${INSTALL_DIR}"

# ── 开机自启 ───────────────────────────────────────────────
if command -v systemctl >/dev/null 2>&1; then
    cp -f "${INSTALL_DIR}/support-files/systemd/mariadb.service" /etc/systemd/system/mysql.service
    systemctl daemon-reload
    systemctl enable mysql.service
    systemctl start mysql.service
else
    cp "${INSTALL_DIR}/support-files/mysql.server" /etc/init.d/mysql
    chmod +x /etc/init.d/mysql
    chkconfig --add mysql
    chkconfig mysql on
    service mysql start
fi


get_or_gen_cred() {
    local user="$1"
    if ! "${ZAPCTL}" cred exists mysql "${user}" >/dev/null 2>&1; then
        log_info "生成并保存 mysql/${user} 凭据" >&2
        "${ZAPCTL}" cred gen mysql "${user}" >/dev/null \
            || { log_error "生成 mysql/${user} 凭据失败" >&2; return 1; }
    fi
    local pass
    pass="$("${ZAPCTL}" cred show mysql "${user}")" \
        || { log_error "读取 mysql/${user} 凭据失败" >&2; return 1; }
    if [ -z "${pass}" ]; then
        log_error "mysql/${user} 凭据为空" >&2
        return 1
    fi
    printf '%s' "${pass}"
}
# 只生成 zapadm 凭据。root 不需要密码：
# MariaDB 10.4+ 的 mariadb-install-db 默认把 root@localhost 配为 unix_socket 认证
# （仅 OS root 经本地 socket 免密登录，原生密码分支为 'invalid'），
# 且 zap 全链路只消费 zapadm 凭据——设置 root 密码既无意义还引入命令行明文，
# 故省略；以下管理操作一律以 OS root 身份经 socket 免密执行。
ZAPADM_PASSWORD="$(get_or_gen_cred zapadm)" || exit 1


# 等待 mariadbd 就绪（最多 60s）
MARIADB_READY=0
for _ in $(seq 1 60); do
    if "${INSTALL_DIR}/bin/mysqladmin" -u root status >/dev/null 2>&1; then
        MARIADB_READY=1
        break
    fi
    sleep 1
done
if [ "${MARIADB_READY}" -ne 1 ]; then
    log_error "mariadbd 60s 内未就绪，请查看 /var/log/mysql/error.log"
    exit 1
fi

# ── zapadm 面板账号（幂等：CREATE IF NOT EXISTS + ALTER 对齐凭据库）──
"${INSTALL_DIR}/bin/mysql" -u root <<SQL
CREATE USER IF NOT EXISTS 'zapadm'@'localhost' IDENTIFIED BY '${ZAPADM_PASSWORD}';
ALTER USER 'zapadm'@'localhost' IDENTIFIED BY '${ZAPADM_PASSWORD}';
GRANT ALL PRIVILEGES ON *.* TO 'zapadm'@'localhost' WITH GRANT OPTION;
FLUSH PRIVILEGES;
SQL

# ── 清除默认匿名空密码账号（''@localhost 等，随 test 库一起创建）──
# 10.4+ 的 mysql.user 是 mysql.global_priv 的视图，不能 DELETE，
# 只能 DROP USER；按行生成（QUOTE 负责转义 host），覆盖任意 host 形态
ANON_SQL="$("${INSTALL_DIR}/bin/mysql" -u root -N -B -e \
    "SELECT CONCAT('DROP USER IF EXISTS ', QUOTE(User), '@', QUOTE(Host), ';') FROM mysql.user WHERE User = '';")" \
    || { log_error "查询匿名账号失败"; exit 1; }
if [ -n "${ANON_SQL}" ]; then
    printf '%s\n' "${ANON_SQL}" | "${INSTALL_DIR}/bin/mysql" -u root
fi

# 安全校验：匿名账号必须清干净
ANON_LEFT="$("${INSTALL_DIR}/bin/mysql" -u root -N -B -e \
    "SELECT CONCAT(User, '@', Host) FROM mysql.user WHERE User = '';")" \
    || { log_error "复查匿名账号失败"; exit 1; }
if [ -n "${ANON_LEFT}" ]; then
    log_error "仍存在匿名账号，请人工处理: ${ANON_LEFT}"
    exit 1
fi



# ── 登记实例信息(apps/<category>/<name>/info.yaml,供「已安装」展示)──────
# svc_name=mysql(systemd unit mysql.service),状态探测与面板启停走
# systemctl;pid_file 保留,作为无 systemd 环境下的兜底探活依据。
ensure_dir "${APP_PATH}"
cat > "${APP_PATH}/info.yaml" <<EOF
svc_name: mysql
instance: mariadb-${MYSQL_SHORT_VERSION}
install_dir: ${INSTALL_DIR}
config_file: /etc/mysql/my.cnf
pid_file: /var/run/mysqld/mysqld.pid
expose:
  - unix:/tmp/mysql.sock
  - tcp:127.0.0.1:3306
tags:
  - database
  - sql
EOF

echo "mysql install successful"

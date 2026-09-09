#!/bin/bash
# MySQL 安装脚本（zap appstore 调用）
# 依赖环境变量（由 zapexec 注入）：ZAP_PATH APPS_DIR PKG_PATH APP_PATH APP_VERSION
set -euo pipefail

source "${ZAP_PATH}/scripts/zap/bash_utils.sh"



# ── 运行时依赖库 ───────────────────────────────────────────
if command -v apt-get >/dev/null 2>&1; then
    apt-get update
    apt-get install -y libncurses5 libaio1 libncurses6 || true
elif command -v yum >/dev/null 2>&1; then
    yum install -y libaio ncurses-compat-libs || true
fi

# ── 系统用户 ───────────────────────────────────────────────
# mysqld 以 mysql 用户/组运行（--user=mysql、chown mysql:mysql 均依赖它）
ensure_user mysql mysql || { log_error "创建 mysql 用户/组失败"; exit 1; }
ensure_dir "/var/log/mysql" || log_warn "安装目录创建失败: /var/log/mysql"
ensure_dir "/var/run/mysqld" || log_warn "安装目录创建失败: /var/run/mysqld"
chown -R mysql:mysql /var/log/mysql /var/run/mysqld

# ── 选择与系统 glibc 匹配的官方二进制包 ───────────────────
# 仅支持 MySQL 8.0+（5.7 及更早版本已移除）
MYSQL_SHORT_VERSION="${MAJOR_VERSION}.${MINOR_VERSION}"
MYSQL_MAJOR="${APP_VERSION%%.*}"
case "${MYSQL_MAJOR}" in
    '' | *[!0-9]*)
        log_error "无法解析 MySQL 版本号: ${APP_VERSION}"
        exit 1 ;;
esac
if [ "${MYSQL_MAJOR}" -lt 8 ]; then
    log_error "MySQL ${APP_VERSION} 不再受支持：已移除 5.7 及更早版本，请选择 8.0+"
    exit 1
fi
# 官方二进制按 glibc 构建，按系统 glibc 选择可用包：
#   glibc >= 2.28 : 9.x / 8.4 / 8.0 全系可用（glibc2.28 构建，更高的 2.3x 向下兼容）
#   glibc 2.17~2.27: 仅 8.0 系列提供 glibc2.17 构建（当前可选 8.0.46）
#   glibc <  2.17 : 无可用官方二进制
GLIBC_VERSION=$(getconf GNU_LIBC_VERSION 2>/dev/null | awk '{print $2}')
GLIBC_MAJOR="${GLIBC_VERSION%%.*}"
GLIBC_MINOR="${GLIBC_VERSION#*.}"
GLIBC_MINOR="${GLIBC_MINOR%%.*}"
case "${GLIBC_MAJOR}${GLIBC_MINOR}" in
    '' | *[!0-9]*)
        log_error "无法探测系统 glibc 版本(取到 '${GLIBC_VERSION:-空}')，无法选择安装包"
        exit 1 ;;
esac

MYSQL_MINOR="${APP_VERSION#*.}"
MYSQL_MINOR="${MYSQL_MINOR%%.*}"
case "${MYSQL_MINOR}" in
    '' | *[!0-9]*)
        log_error "无法解析 MySQL 次版本号: ${APP_VERSION}"
        exit 1 ;;
esac

if [ "${GLIBC_MAJOR}" -gt 2 ] \
    || { [ "${GLIBC_MAJOR}" -eq 2 ] && [ "${GLIBC_MINOR}" -ge 28 ]; }; then
    GLIBC_PKG="2.28"
elif [ "${GLIBC_MAJOR}" -eq 2 ] && [ "${GLIBC_MINOR}" -ge 17 ]; then
    # 旧系统（CentOS 7 / Debian 9 等）：只有 8.0 系列有 glibc2.17 构建
    if [ "${MYSQL_MAJOR}" -ne 8 ] || [ "${MYSQL_MINOR}" -ne 0 ]; then
        log_error "系统 glibc ${GLIBC_MAJOR}.${GLIBC_MINOR} 仅支持 MySQL 8.0 系列（当前可选 8.0.46）"
        log_error "MySQL ${APP_VERSION} 需要 glibc >= 2.28，请改选 8.0.46，或升级系统（建议 Debian 10+ / Ubuntu 20.04+ / RHEL 8+）"
        exit 1
    fi
    GLIBC_PKG="2.17"
else
    log_error "系统 glibc ${GLIBC_MAJOR}.${GLIBC_MINOR} 过低：MySQL 官方二进制需要 glibc >= 2.17"
    exit 1
fi
if [ "${MYSQL_MAJOR}" -eq 8 ] && [ "${MYSQL_MINOR}" -eq 0 ]; then
    # 安装 8.0 系列时，强制使用 8.0.46（glibc2.17 构建）以兼容旧系统
    GLIBC_PKG="2.17"
fi

log_info "系统 glibc ${GLIBC_MAJOR}.${GLIBC_MINOR}，使用 glibc${GLIBC_PKG} 官方包"
PKG_TARBALL="mysql-${APP_VERSION}-linux-glibc${GLIBC_PKG}-x86_64-minimal.tar.xz"
PKG_EXTRACT_DIR="mysql-${APP_VERSION}-linux-glibc${GLIBC_PKG}-x86_64-minimal"

cd "${PKG_PATH}"
if [ ! -f "${PKG_TARBALL}" ]; then
    log_info "下载 mysql: ${PKG_TARBALL}"
    download_file "https://mirrors.zap.cn/pkg/mysql/${PKG_TARBALL}" "${PKG_TARBALL}" || true
fi
tar xf "${PKG_TARBALL}" -C "${APPS_DIR}"

# ── 安装目录（解压目录名含 glibc 标识，统一重命名为 mysql-版本） mysql-8.0 ──
INSTALL_DIR="${APPS_DIR}/mysql-${MYSQL_SHORT_VERSION}"
if [ -d "${APPS_DIR}/${PKG_EXTRACT_DIR}" ] && [ ! -d "${INSTALL_DIR}" ]; then
    mv "${APPS_DIR}/${PKG_EXTRACT_DIR}" "${INSTALL_DIR}"
fi
if [ ! -d "${INSTALL_DIR}" ]; then
    echo "Error unpacking mysql: ${INSTALL_DIR} not found"
    exit 1
fi

if [ "${SET_DEFAULT:-false}" = "true" ]; then
    ln -sf "${INSTALL_DIR}/bin/mysql" /usr/local/bin/mysql
    ln -sf "${INSTALL_DIR}/bin/mysqldump" /usr/local/bin/mysqldump
    ln -sf "${INSTALL_DIR}/bin/myisamchk" /usr/local/bin/myisamchk
    ln -sf "${INSTALL_DIR}/bin/mysqld_safe" /usr/local/bin/mysqld_safe
    ln -sf "${INSTALL_DIR}/bin/mysqlcheck" /usr/local/bin/mysqlcheck
fi

# 软链接到 /usr/local/mysql
if [ ! -d "/usr/local/mysql" ]; then
    ln -sf "${INSTALL_DIR}" /usr/local/mysql
fi


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

cat > /etc/mysql/my.cnf <<EOF
[client]
port            = 3306
socket          = /var/run/mysqld/mysqld.sock
default-character-set = utf8mb4

[mysql]
default-character-set = utf8mb4

[mysqld]
user            = mysql
port            = 3306
socket          = /var/run/mysqld/mysqld.sock
basedir        = /usr/local/mysql
datadir         = /usr/local/mysql/data
log-error       = /var/log/mysql/error.log
pid-file        = /var/run/mysqld/mysqld.pid
skip-external-locking
skip-name-resolve

max_allowed_packet              = 32M


slow_query_log_file = /var/log/mysql/mysql-slow.log
slow_query_log      = 1
long_query_time     = 1


character-set-server = utf8mb4
collation-server     = utf8mb4_0900_ai_ci
log_timestamps       = SYSTEM


# 默认 128M 太小，（建议设为总内存的 50% - 70%)
innodb_buffer_pool_size = 1G 

max_connections         = 500
max_connect_errors       = 1000

log_bin         = mysql-bin
binlog_format   = ROW
binlog_expire_logs_seconds = 604800 

EOF

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

# ── 账号凭据（root / zapadm）──────────────────────────────
# 密码统一由凭据库托管（/etc/zap/credentials/mysql_<user>.cred，0400 加密存储）：
# 重装 / 升级时复用已有凭据，不重复生成
# 注：本函数在命令替换 $() 内调用，日志一律走 stderr，避免污染取回的密码
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
MYSQL_ROOT_PASSWORD="$(get_or_gen_cred root)" || exit 1
ZAPADM_PASSWORD="$(get_or_gen_cred zapadm)" || exit 1

# 等待 mysqld 就绪（最多 60s）
MYSQLD_READY=0
for _ in $(seq 1 60); do
    if bin/mysqladmin -u root status >/dev/null 2>&1; then
        MYSQLD_READY=1
        break
    fi
    sleep 1
done
if [ "${MYSQLD_READY}" -ne 1 ]; then
    log_error "mysqld 60s 内未就绪，请查看 /var/log/mysql/error.log"
    exit 1
fi

# ── 设置 root 密码（接管 --initialize-insecure 产生的空密码 root）──
bin/mysql -u root <<SQL
ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';
SQL

# 此后凭据经 0600 临时配置文件传入（mktemp 默认 0600）：
# 1) 避免命令行明文（ps 对同机用户可见） 2) 消除 "Using a password..." 告警
ROOT_CNF="$(mktemp /tmp/mysql-root.XXXXXX.cnf)"
trap 'rm -f "${ROOT_CNF:-}"' EXIT
printf '[client]\nuser = root\npassword = %s\n' "${MYSQL_ROOT_PASSWORD}" > "${ROOT_CNF}"

# ── zapadm 面板账号 + 清除空密码（单次会话幂等执行）──────
# CREATE IF NOT EXISTS + ALTER 保证重装 / 密码轮换后与凭据库一致；
# DELETE 清除匿名账号（''@'localhost' 等），避免无密码旁路登录；
# --defaults-extra-file 必须置于其它选项之前
bin/mysql --defaults-extra-file="${ROOT_CNF}" <<SQL
CREATE USER IF NOT EXISTS 'zapadm'@'localhost' IDENTIFIED BY '${ZAPADM_PASSWORD}';
ALTER USER 'zapadm'@'localhost' IDENTIFIED BY '${ZAPADM_PASSWORD}';
GRANT ALL PRIVILEGES ON *.* TO 'zapadm'@'localhost' WITH GRANT OPTION;
DELETE FROM mysql.user WHERE User = '';
FLUSH PRIVILEGES;
SQL

# 安全校验 1：不得残留空密码账号（root/zapadm 已设密；锁定/系统账号除外）
EMPTY_PW_USERS="$(bin/mysql --defaults-extra-file="${ROOT_CNF}" -N -B -e \
    "SELECT CONCAT(User, '@', Host) FROM mysql.user WHERE authentication_string = '' AND plugin IN ('mysql_native_password','caching_sha2_password') AND account_locked = 'N';")" \
    || { log_error "查询空密码账号失败"; exit 1; }
if [ -n "${EMPTY_PW_USERS}" ]; then
    log_error "仍存在空密码账号，请人工处理: ${EMPTY_PW_USERS}"
    exit 1
fi

# 安全校验 2：不带凭据的空密码连接必须失败
if bin/mysql -u root -e "SELECT 1" </dev/null >/dev/null 2>&1; then
    log_error "root 空密码仍可登录，安全加固失败"
    exit 1
fi

# restart mysql
log_info "restart mysql"
if command -v systemctl >/dev/null 2>&1; then
    systemctl restart mysql.service
elif command -v service >/dev/null 2>&1; then
    service mysql restart
fi
log_info "mysql restart done"

# ── 登记实例信息(apps/<category>/<name>/info.yaml,供「已安装」展示)──────
# svc_name=mysql(systemd unit mysql.service),状态探测与面板启停走 systemctl;
# pid_file 保留,作为无 systemd 环境下的兜底探活依据。
ensure_dir "${APP_PATH}"
cat > "${APP_PATH}/info.yaml" <<EOF
svc_name: mysql
instance: mysql-${MYSQL_SHORT_VERSION}
install_dir: ${INSTALL_DIR}
config_file: /etc/mysql/my.cnf
pid_file: /var/run/mysqld/mysqld.pid
expose:
  - unix:/var/run/mysqld/mysqld.sock
  - tcp:127.0.0.1:3306
tags:
  - database
  - sql
EOF

echo "mysql install successful"

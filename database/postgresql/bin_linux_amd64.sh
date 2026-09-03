#!/bin/bash
# PostgreSQL 安装脚本（zap appstore 调用，源码编译）
# 依赖环境变量（由 zapexec 注入）：ZAP_PATH APPS_DIR PKG_PATH APP_PATH APP_VERSION MAJOR_VERSION CPU_NUM BUILD_PATH
set -euo pipefail

source "${ZAP_PATH}/scripts/zap/bash_utils.sh"

# ── 编译依赖 ───────────────────────────────────────────────
if command -v apt-get >/dev/null 2>&1; then
    apt-get update
    apt-get install -y build-essential libreadline-dev zlib1g-dev || true
elif command -v yum >/dev/null 2>&1; then
    yum install -y gcc make readline-devel zlib-devel || true
fi

# ── 系统用户 ───────────────────────────────────────────────
if ! id postgres >/dev/null 2>&1; then
    useradd -r -m -s /bin/bash postgres
fi

INSTALL_DIR="${APPS_DIR}/postgresql-${MAJOR_VERSION}"
DATA_DIR="${INSTALL_DIR}/data"
SRC_DIR="${BUILD_PATH}/postgresql-${APP_VERSION}"

# ── 下载并解压源码 ─────────────────────────────────────────
TARBALL="postgresql-${APP_VERSION}.tar.gz"
cd "${PKG_PATH}"
if [ ! -f "${TARBALL}" ]; then
    if ! wget "https://ftp.postgresql.org/pub/source/v${APP_VERSION}/${TARBALL}" -O "${TARBALL}"; then
        echo "Error download postgresql: ${TARBALL}"
        exit 1
    fi
fi

rm -rf "${BUILD_PATH}"
mkdir -p "${BUILD_PATH}"
tar xzf "${PKG_PATH}/${TARBALL}" -C "${BUILD_PATH}"

# ── 编译安装 ───────────────────────────────────────────────
cd "${SRC_DIR}"
./configure --prefix="${INSTALL_DIR}" --with-pgport=5432
make -j "${CPU_NUM:-1}"
make install

# ── 初始化数据目录 ─────────────────────────────────────────
mkdir -p "${DATA_DIR}"
chown -R postgres:postgres "${INSTALL_DIR}"
su - postgres -c "${INSTALL_DIR}/bin/initdb -D '${DATA_DIR}' -E UTF8 --no-locale"

# ── systemd 服务 ───────────────────────────────────────────
mkdir -p "${INSTALL_DIR}/log"
chown -R postgres:postgres "${INSTALL_DIR}/log"
cat > /etc/systemd/system/postgresql.service <<EOF
[Unit]
Description=PostgreSQL ${APP_VERSION} database server
After=network.target

[Service]
Type=forking
User=postgres
Group=postgres
ExecStart=${INSTALL_DIR}/bin/pg_ctl -D ${DATA_DIR} -l ${INSTALL_DIR}/log/postgresql.log start
ExecStop=${INSTALL_DIR}/bin/pg_ctl -D ${DATA_DIR} stop -m fast
ExecReload=${INSTALL_DIR}/bin/pg_ctl -D ${DATA_DIR} reload
PIDFile=${DATA_DIR}/postmaster.pid

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable postgresql.service
systemctl start postgresql.service

# ── 创建 zap 管理账号 ──────────────────────────────────────
PG_PASSWORD=$(openssl rand -hex 8 2>/dev/null || true)
if [ -z "${PG_PASSWORD}" ]; then
    PG_PASSWORD=$(< /dev/urandom tr -dc A-Za-z0-9_ | head -c9)
fi

for _ in $(seq 1 30); do
    if su - postgres -c "${INSTALL_DIR}/bin/pg_isready -h 127.0.0.1 -p 5432" >/dev/null 2>&1; then
        break
    fi
    sleep 1
done

su - postgres -c "${INSTALL_DIR}/bin/psql -c \"CREATE USER zapadm WITH SUPERUSER PASSWORD '${PG_PASSWORD}';\""

wzap_conf postgresql_u "zapadm"
wzap_conf postgresql_p "${PG_PASSWORD}"
${ZAPCTL} config set postgresql_u "zapadm"
${ZAPCTL} config set postgresql_p "${PG_PASSWORD}"

# ── 登记实例信息(apps/<category>/<name>/info.yaml,供「已安装」展示)──────
# svc_name=postgresql(systemd unit postgresql.service),状态探测与面板启停走
# systemctl;pid_file 保留作兜底。config_file 修正为 initdb 实际生成的
# ${DATA_DIR}/postgresql.conf(原登记 ${INSTALL_DIR}/postgresql.conf 并不存在)。
ensure_dir "${APP_PATH}"
cat > "${APP_PATH}/info.yaml" <<EOF
svc_name: postgresql
instance: postgresql${MAJOR_VERSION}
install_dir: ${INSTALL_DIR}
config_file: ${DATA_DIR}/postgresql.conf
pid_file: ${DATA_DIR}/postmaster.pid
expose: tcp:127.0.0.1:5432
tags:
  - database
  - sql
EOF

echo "postgresql install successful"

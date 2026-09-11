#!/bin/bash
# phpMyAdmin 卸载脚本（zap appstore 调用）
#
# 依赖环境变量（由 zapexec 注入）：ZAP_PATH APPS_DIR APP_PATH ZAP_DATA_PATH
#                                  APP_VERSION MAJOR_VERSION MINOR_VERSION
# 选项（app.yaml options.uninstall）：
#   KEEP_CONFIG   true = 保留 config.inc.php 到 ${APPS_DIR}/phpmyadmin-config.inc.php.bak
#
# 说明：仅删除程序目录与 Nginx 配置，不触碰数据库数据。
set -euo pipefail

source "${ZAP_PATH}/scripts/zap/bash_utils.sh"
assert_root || exit 1

APP_TITLE="phpMyAdmin"
KEEP_CONFIG_OPT="${KEEP_CONFIG:-false}"
LINK_DIR="${APPS_DIR}/phpmyadmin"
NGINX_AVAIL="/etc/zap/webservers/nginx/sites-available/zap-app-phpmyadmin.conf"
NGINX_ENABLED="/etc/zap/webservers/nginx/sites-enabled/zap-app-phpmyadmin.conf"

# 安装目录以登记信息为准（版本目录名可能随安装版本变化）
INSTALL_DIR=""
INFO_FILE="${APP_PATH}/info.yaml"
if [ -f "${INFO_FILE}" ]; then
    INSTALL_DIR="$(grep -m1 '^install_dir:' "${INFO_FILE}" 2>/dev/null | sed 's/^install_dir:[[:space:]]*//' || true)"
fi
if [ -z "${INSTALL_DIR}" ] || [ ! -d "${INSTALL_DIR}" ]; then
    INSTALL_DIR="${APPS_DIR}/phpmyadmin-${MAJOR_VERSION:-}.${MINOR_VERSION:-}"
fi
log_info "准备卸载 ${APP_TITLE}（安装目录 ${INSTALL_DIR}）"

# ── 按需保留配置 ────────────────────────────────────────────
if [ "${KEEP_CONFIG_OPT}" = "true" ] && [ -f "${INSTALL_DIR}/config.inc.php" ]; then
    BAK_FILE="${APPS_DIR}/phpmyadmin-config.inc.php.bak"
    if cp -f "${INSTALL_DIR}/config.inc.php" "${BAK_FILE}"; then
        log_ok "已保留配置：${BAK_FILE}"
    else
        log_warn "保留配置失败（继续卸载）：${BAK_FILE}"
    fi
fi

# ── 移除 Nginx 配置 ─────────────────────────────────────────
if [ -e "${NGINX_ENABLED}" ] || [ -L "${NGINX_ENABLED}" ]; then
    rm -f "${NGINX_ENABLED}"
    log_ok "已移除启用配置：${NGINX_ENABLED}"
fi
if [ -f "${NGINX_AVAIL}" ]; then
    rm -f "${NGINX_AVAIL}"
    log_ok "已移除站点配置：${NGINX_AVAIL}"
fi

reload_nginx() {
    if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet nginx 2>/dev/null; then
        systemctl reload nginx && return 0
    fi
    local n
    for n in "${APPS_DIR}"/nginx-*/sbin/nginx /usr/sbin/nginx /usr/local/nginx/sbin/nginx; do
        [ -x "${n}" ] && {
            "${n}" -t >/dev/null 2>&1 && "${n}" -s reload && return 0
        }
    done
    if command -v nginx >/dev/null 2>&1; then
        nginx -t >/dev/null 2>&1 && nginx -s reload && return 0
    fi
    return 1
}
if reload_nginx; then
    log_ok "Nginx 已重载"
else
    log_warn "Nginx 重载失败，请手动执行 nginx -s reload 或 systemctl reload nginx"
fi

# ── 删除程序目录（含软链）──────────────────────────────────
if [ -L "${LINK_DIR}" ]; then
    rm -f "${LINK_DIR}"
    log_ok "已移除软链：${LINK_DIR}"
fi
if [ -d "${INSTALL_DIR}" ]; then
    rm -rf "${INSTALL_DIR}"
    log_ok "已删除安装目录：${INSTALL_DIR}"
else
    log_warn "安装目录不存在（可能已被清理）：${INSTALL_DIR}"
fi

log_ok "${APP_TITLE} uninstalling successful"

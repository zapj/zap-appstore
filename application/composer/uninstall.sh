#!/bin/bash
# Composer 卸载脚本（zap appstore 调用）
# 依赖环境变量（由 zapexec 注入）：ZAP_PATH APPS_DIR PKG_PATH APP_PATH
set -euo pipefail

source "${ZAP_PATH}/scripts/zap/bash_utils.sh"

COMPOSER_DIR="${APPS_DIR}/composer"
COMPOSER_BIN="${COMPOSER_DIR}/composer"

# ── 还原全局配置中的 pkg.xyz 镜像（仅当仍指向该镜像时才移除，恢复官方源）──
if command -v php >/dev/null 2>&1 && [ -f "${COMPOSER_BIN}" ]; then
    PHP_BIN="$(command -v php)"
    if "${PHP_BIN}" "${COMPOSER_BIN}" config -g repos.packagist.url 2>/dev/null \
        | grep -q "packagist.phpcomposer.com"; then
        "${PHP_BIN}" "${COMPOSER_BIN}" config -g --unset repos.packagist
        log_info "已移除全局配置中的 pkg.xyz 镜像，Packagist 恢复官方源"
    fi
fi

# ── 移除全局命令链接（仅当指向本实例）──────────────────────
if [ -L /usr/local/bin/composer ] && [ "$(readlink /usr/local/bin/composer)" = "${COMPOSER_BIN}" ]; then
    rm -f /usr/local/bin/composer
    log_info "已移除全局命令 /usr/local/bin/composer"
fi

# ── 删除安装目录 ───────────────────────────────────────────
rm -rf "${COMPOSER_DIR}"

log_info "Composer 已卸载"

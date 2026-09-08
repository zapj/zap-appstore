#!/bin/bash
# Composer 安装脚本（zap appstore 调用）
# 依赖环境变量（由 zapexec 注入）：ZAP_PATH APPS_DIR PKG_PATH APP_PATH APP_VERSION
# 可选（options，值原样注入）：
#   INSTALL_SOURCE select —— official（getcomposer.org，默认）/ mirror（pkg.xyz 中国镜像），安装器下载源
#   ENABLE_MIRROR  bool —— "true" 时把 Packagist 依赖源切换为 pkg.xyz 镜像并写入全局配置
#
# 说明：
#   * Composer 为单文件 phar，安装到 ${APPS_DIR}/composer/composer，固定注册
#     全局命令 /usr/local/bin/composer（Composer 全局唯一，无需"设为默认"开关）。
#   * 依赖系统默认 PHP（php 命令），安装前需先安装 PHP。
set -euo pipefail

source "${ZAP_PATH}/scripts/zap/bash_utils.sh"



# ── PHP 依赖检查 ───────────────────────────────────────────
if ! command -v php >/dev/null 2>&1; then
    log_error "未找到 php 命令：请先在应用商店安装 PHP（安装时勾选「设为全局默认 PHP」）后再安装 Composer"
    exit 1
fi
PHP_BIN="$(command -v php)"
log_info "使用 PHP: $("${PHP_BIN}" -v | head -n1)"
export HOME="/root"
export COMPOSER_HOME="$HOME/.config/composer"
log_info "HOME=${HOME:-}"

# ── 安装位置 ───────────────────────────────────────────────
COMPOSER_DIR="${APPS_DIR}/composer"
COMPOSER_BIN="${COMPOSER_DIR}/composer"
ensure_dir "${COMPOSER_DIR}"

# ── 安装器下载源（options.INSTALL_SOURCE）───────────────────
INSTALLER_URL="https://getcomposer.org/installer"
SRC_NAME="getcomposer.org（官方源）"
case "${INSTALL_SOURCE:-official}" in
    mirror)
        INSTALLER_URL="https://install.phpcomposer.com/installer"
        SRC_NAME="pkg.xyz 中国镜像（install.phpcomposer.com）"
        ;;
    official) ;;
    *)
        log_warn "未知下载源「${INSTALL_SOURCE:-}」，回退官方源"
        ;;
esac

INST_TMP="$(mktemp -d)"
trap 'rm -rf "${INST_TMP}"' EXIT

log_info "从 ${SRC_NAME} 下载 Composer 安装器…"
# 官方推荐 php copy 方式；php 未开启 allow_url_fopen 时回退 curl / wget
if ! "${PHP_BIN}" -r "copy('${INSTALLER_URL}', '${INST_TMP}/composer-setup.php');" >/dev/null 2>&1 \
    || [ ! -s "${INST_TMP}/composer-setup.php" ]; then
    log_warn "php copy 下载失败，改用 curl/wget 下载安装器"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "${INSTALLER_URL}" -o "${INST_TMP}/composer-setup.php"
    elif command -v wget >/dev/null 2>&1; then
        wget -q "${INSTALLER_URL}" -O "${INST_TMP}/composer-setup.php"
    else
        log_error "下载失败：PHP 未开启 allow_url_fopen，且系统无 curl / wget"
        exit 1
    fi
fi
if [ ! -s "${INST_TMP}/composer-setup.php" ]; then
    log_error "Composer 安装器下载失败（文件为空）"
    exit 1
fi

log_info "运行 Composer 安装器…"
"${PHP_BIN}" "${INST_TMP}/composer-setup.php" \
    --install-dir="${COMPOSER_DIR}" \
    --filename=composer \
    --quiet
rm -f "${INST_TMP}/composer-setup.php"

if [ ! -f "${COMPOSER_BIN}" ]; then
    log_error "Composer 安装失败：未生成 ${COMPOSER_BIN}"
    exit 1
fi

# ── 注册到全局命令 ─────────────────────────────────────────
ln -sf "${COMPOSER_BIN}" /usr/local/bin/composer
log_info "已注册全局命令 /usr/local/bin/composer"

# ── 启用全局代理（options.ENABLE_MIRROR）──────────────────
# 官方推荐方式：修改全局配置文件（composer config -g 写 ~/.config/composer/config.json），
# 对当前系统用户所有项目生效，无需逐个项目配置。
if [ "${ENABLE_MIRROR:-false}" = "true" ]; then
    "${PHP_BIN}" "${COMPOSER_BIN}" config -g repo.packagist composer https://packagist.phpcomposer.com
    log_info "已启用全局代理：Packagist 源切换为 pkg.xyz 中国全量镜像（写入全局配置文件 config.json）"
else
    log_info "未启用全局代理，保持官方 Packagist 源"
fi

# ── 登记实例信息（apps/<category>/<name>/info.yaml）────────
ensure_dir "${APP_PATH}"
cat > "${APP_PATH}/info.yaml" <<EOF
install_dir: ${COMPOSER_DIR}
global_bin: /usr/local/bin/composer
EOF

VERSION_LINE="$("${PHP_BIN}" "${COMPOSER_BIN}" --version --no-ansi | head -n1)"
log_info "Composer 安装成功: ${VERSION_LINE}"

#!/usr/bin/env bash
# =============================================================================
# WSL 初始化配置脚本
# 功能：配置中文 Locale、修改 /etc/wsl.conf、安装常用软件包
# 用法：sudo bash wsl_init.sh [默认用户名]
# =============================================================================

set -euo pipefail

# ── 颜色输出 ─────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

# ── 权限检查 ──────────────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    error "请使用 root 权限运行此脚本：sudo bash $0 [用户名]"
fi

# ── 获取默认用户名 ─────────────────────────────────────────────────────────────
DEFAULT_USER="${1:-}"

if [[ -z "$DEFAULT_USER" ]]; then
    # 未通过参数传入时，交互式询问
    read -rp "请输入 WSL 默认登录用户名（直接回车跳过）: " DEFAULT_USER
fi

# ── 分隔线 ────────────────────────────────────────────────────────────────────
echo ""
echo "=============================================="
echo "       WSL 初始化配置脚本 开始执行"
echo "=============================================="
echo ""

# =============================================================================
# 1. 配置中文 Locale
# =============================================================================
info "步骤 1/3：配置中文 Locale (zh_CN.UTF-8) ..."

# 安装 locales 包（如未安装）
if ! dpkg -l locales &>/dev/null; then
    apt-get update -qq
    apt-get install -y locales
fi

# 启用 zh_CN.UTF-8
if ! grep -q "^zh_CN.UTF-8" /etc/locale.gen 2>/dev/null; then
    echo "zh_CN.UTF-8 UTF-8" >> /etc/locale.gen
fi
# 同时确保 en_US.UTF-8 也可用（避免部分工具报错）
if ! grep -q "^en_US.UTF-8" /etc/locale.gen 2>/dev/null; then
    echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
fi

locale-gen

# 写入系统级默认 Locale
cat > /etc/default/locale <<'EOF'
LANG=zh_CN.UTF-8
LANGUAGE=zh_CN:zh
LC_ALL=zh_CN.UTF-8
EOF

# 同步到当前 Shell 环境
export LANG=zh_CN.UTF-8
export LC_ALL=zh_CN.UTF-8

success "中文 Locale 配置完成。"

# =============================================================================
# 2. 修改 /etc/wsl.conf
# =============================================================================
info "步骤 2/3：配置 /etc/wsl.conf ..."

WSL_CONF="/etc/wsl.conf"

# 备份原文件
if [[ -f "$WSL_CONF" ]]; then
    cp "$WSL_CONF" "${WSL_CONF}.bak.$(date +%Y%m%d_%H%M%S)"
    info "原 wsl.conf 已备份。"
fi

# ── 辅助函数：写入或更新 wsl.conf 中的 section/key ──────────────────────────
# 用法：set_wsl_conf <section> <key> <value>
set_wsl_conf() {
    local section="$1"
    local key="$2"
    local value="$3"
    local section_pattern="^\[${section}\]"

    if grep -q "$section_pattern" "$WSL_CONF" 2>/dev/null; then
        # section 已存在
        if grep -A 20 "$section_pattern" "$WSL_CONF" | grep -q "^${key}\s*="; then
            # key 已存在 → 更新
            sed -i "/^${key}\s*=/s|.*|${key}=${value}|" "$WSL_CONF"
        else
            # key 不存在 → 在 section 后追加
            sed -i "/^${section_pattern}/a ${key}=${value}" "$WSL_CONF"
        fi
    else
        # section 不存在 → 追加整个块
        printf '\n[%s]\n%s=%s\n' "$section" "$key" "$value" >> "$WSL_CONF"
    fi
}

# 确保文件存在
touch "$WSL_CONF"

# 写入 [network] generateResolvConf=false
set_wsl_conf "network" "generateResolvConf" "false"

# 写入 [user] default=<用户名>（仅当用户名非空时）
if [[ -n "$DEFAULT_USER" ]]; then
    # 校验用户是否存在
    if id "$DEFAULT_USER" &>/dev/null; then
        set_wsl_conf "user" "default" "$DEFAULT_USER"
        success "wsl.conf [user] default 已设置为：$DEFAULT_USER"
    else
        warn "用户 '$DEFAULT_USER' 不存在，跳过写入 [user] default。"
        warn "你可以在用户创建后手动执行：echo -e '[user]\ndefault=$DEFAULT_USER' >> /etc/wsl.conf"
    fi
else
    warn "未指定默认用户，跳过写入 [user] default。"
fi

success "/etc/wsl.conf 配置完成，当前内容如下："
echo "----------------------------------------------"
cat "$WSL_CONF"
echo "----------------------------------------------"

# =============================================================================
# 3. 安装常用软件包
# =============================================================================
info "步骤 3/3：安装常用软件包 ..."

# ── 3.1 更新软件源 ────────────────────────────────────────────────────────────
info "  更新 apt 软件源 ..."
apt-get update -qq

# ── 3.2 安装基础依赖 ───────────────────────────────────────────────────────────
info "  安装基础依赖 ..."
apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    apt-transport-https \
    wget \
    lsof \
    unzip \
    zip

# ── 3.3 安装 Git ───────────────────────────────────────────────────────────────
info "  安装 Git ..."
apt-get install -y git
success "  Git $(git --version) 安装完成。"

# ── 3.4 安装 Python 3 & pip ───────────────────────────────────────────────────
info "  安装 Python3 & pip ..."
apt-get install -y python3 python3-pip python3-venv python3-dev
# 创建 python → python3 的软链（如不存在）
if ! command -v python &>/dev/null; then
    ln -sf /usr/bin/python3 /usr/local/bin/python
fi
success "  Python $(python3 --version) 安装完成。"
success "  pip $(pip3 --version | awk '{print $2}') 安装完成。"

# ── 3.5 安装 Docker Engine ────────────────────────────────────────────────────
info "  安装 Docker Engine ..."

# 移除旧版本（如有）
for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do
    apt-get remove -y "$pkg" 2>/dev/null || true
done

# 添加 Docker 官方 GPG 密钥
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg \
    | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

# 添加 Docker 软件源
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/debian \
$(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  > /etc/apt/sources.list.d/docker.list

apt-get update -qq

apt-get install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin

# Docker 自启动
sudo systemctl start docker
sudo systemctl enable docker
sudo systemctl daemon-reload

success "  Docker $(docker --version) 安装完成。"

# ── 3.6 安装 Docker Compose (Plugin 方式) ────────────────────────────────────
info "  安装 Docker Compose (Plugin) ..."
apt-get install -y docker-compose-plugin

# 兼容旧命令 docker-compose（创建软链）
if ! command -v docker-compose &>/dev/null; then
    ln -sf /usr/libexec/docker/cli-plugins/docker-compose /usr/local/bin/docker-compose 2>/dev/null \
    || ln -sf "$(find /usr/lib/docker/cli-plugins/ -name docker-compose 2>/dev/null | head -1)" \
              /usr/local/bin/docker-compose 2>/dev/null \
    || true
fi

success "  Docker Compose $(docker compose version) 安装完成。"

# ── 3.7 将当前/默认用户加入 docker 组 ────────────────────────────────────────
if [[ -n "$DEFAULT_USER" ]] && id "$DEFAULT_USER" &>/dev/null; then
    usermod -aG docker "$DEFAULT_USER"
    success "  用户 '$DEFAULT_USER' 已加入 docker 用户组（重新登录后生效）。"
elif [[ -n "${SUDO_USER:-}" ]] && id "$SUDO_USER" &>/dev/null; then
    usermod -aG docker "$SUDO_USER"
    success "  用户 '$SUDO_USER' 已加入 docker 用户组（重新登录后生效）。"
fi

# =============================================================================
# 完成汇总
# =============================================================================
echo ""
echo "=============================================="
echo -e "${GREEN}       所有配置已完成！${NC}"
echo "=============================================="
echo ""
echo "  ✔  中文 Locale：zh_CN.UTF-8"
echo "  ✔  /etc/wsl.conf 已更新"
echo "  ✔  Git       : $(git --version)"
echo "  ✔  Python    : $(python3 --version)"
echo "  ✔  pip       : pip $(pip3 --version | awk '{print $2}')"
echo "  ✔  Docker    : $(docker --version)"
echo "  ✔  Compose   : $(docker compose version)"
echo ""
warn "⚠  请在 PowerShell 中执行 'wsl --shutdown' 并重新启动 WSL，使 wsl.conf 生效。"
echo ""
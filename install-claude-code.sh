#!/usr/bin/env bash
# ============================================================
#  Claude Code + DeepSeek v4 一键安装脚本 (macOS / Linux)
#
#  用法:
#    bash install-claude-code.sh [--force] [--model 'deepseek-v4-pro[1m]'] [--no-mirror]
#
#  动作:
#    1. 检测 / 安装 Node.js LTS (>=18)
#    2. 检测 / 安装 Python 3.12+
#    3. 检测 / 安装 Git
#    4. 配置 npm 用户级 prefix (免 sudo) + 国内镜像
#    5. 全局安装 @anthropic-ai/claude-code
#    6. 写入 shell rc 配置 环境变量 ANTHROPIC_* 到 shell rc (~/.zshrc / ~/.bashrc / ~/.profile)
# ============================================================

set -euo pipefail

_main() {

    # ---------- 配色 / 打印 ----------
    if [ -t 1 ]; then
        RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; CYAN=$'\033[36m'; NC=$'\033[0m'
    else
        RED=''; GREEN=''; YELLOW=''; CYAN=''; NC=''
    fi
    step() { printf '\n%s==> %s%s\n'   "$CYAN"   "$*" "$NC"; }
    ok()   { printf '%s[OK]   %s%s\n'  "$GREEN"  "$*" "$NC"; }
    warn() { printf '%s[WARN] %s%s\n'  "$YELLOW" "$*" "$NC"; }
    err()  { printf '%s[ERR]  %s%s\n'  "$RED"    "$*" "$NC" >&2; }
    die()  { err "$*"; exit 1; }

    # ---------- 参数 ----------
    FORCE=0
    MODEL='deepseek-v4-pro[1m]'
    NO_MIRROR=0
    while [ $# -gt 0 ]; do
        case "$1" in
            --force|-f)  FORCE=1; shift ;;
            --model)     MODEL="${2:?--model 需要值}"; shift 2 ;;
            --no-mirror) NO_MIRROR=1; shift ;;
            -h|--help)   sed -n '2,16p' "$0" 2>/dev/null || true; exit 0 ;;
            *)           die "未知参数: $1" ;;
        esac
    done

    # ---------- 横幅 ----------
    printf '\n%s============================================================%s\n' "$CYAN" "$NC"
    printf '%s  Claude Code + DeepSeek v4 一键安装脚本 (macOS / Linux)%s\n'      "$CYAN" "$NC"
    printf '%s============================================================%s\n' "$CYAN" "$NC"

    # ---------- 检测 OS / 包管理器 / sudo ----------
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')

    _sudo() {
        if [ "$(id -u)" -eq 0 ]; then "$@"
        elif command -v sudo >/dev/null 2>&1; then command sudo "$@"
        else die "需要 root 或 sudo 权限来执行: $*"
        fi
    }

    PM=''
    case "$OS" in
        darwin)
            # ---- 中国镜像加速 (中科大 USTC), 对全部 brew 操作生效 ----
            export HOMEBREW_INSTALL_FROM_API=1
            export HOMEBREW_API_DOMAIN="https://mirrors.ustc.edu.cn/homebrew-bottles/api"
            export HOMEBREW_BOTTLE_DOMAIN="https://mirrors.ustc.edu.cn/homebrew-bottles"
            export HOMEBREW_BREW_GIT_REMOTE="https://mirrors.ustc.edu.cn/brew.git"
            export HOMEBREW_CORE_GIT_REMOTE="https://mirrors.ustc.edu.cn/homebrew-core.git"
            export HOMEBREW_NO_AUTO_UPDATE=1
            export HOMEBREW_NO_ANALYTICS=1

            if ! command -v brew >/dev/null 2>&1; then
                step "未检测到 Homebrew, 准备安装 (USTC 镜像)"
                NONINTERACTIVE=1 /bin/bash -c \
                    "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
                if   [ -x /opt/homebrew/bin/brew ]; then eval "$(/opt/homebrew/bin/brew shellenv)"
                elif [ -x /usr/local/bin/brew ];   then eval "$(/usr/local/bin/brew shellenv)"
                fi
                # 已装 brew 用户也建议把 git remote 切到镜像 (一次性, 重跑无副作用)
                if command -v brew >/dev/null 2>&1; then
                    BREW_REPO=$(brew --repo 2>/dev/null)
                    [ -d "$BREW_REPO/.git" ] && \
                        git -C "$BREW_REPO" remote set-url origin \
                        "$HOMEBREW_BREW_GIT_REMOTE" 2>/dev/null || true
                fi
            fi
            PM=brew
            ;;
        linux)
            if   command -v apt-get >/dev/null 2>&1; then PM=apt
            elif command -v dnf     >/dev/null 2>&1; then PM=dnf
            elif command -v yum     >/dev/null 2>&1; then PM=yum
            elif command -v pacman  >/dev/null 2>&1; then PM=pacman
            elif command -v zypper  >/dev/null 2>&1; then PM=zypper
            elif command -v apk     >/dev/null 2>&1; then PM=apk
            else die "未识别的 Linux 包管理器 (支持 apt/dnf/yum/pacman/zypper/apk)"
            fi
            ;;
        *) die "不支持的 OS: $OS (仅 macOS / Linux)" ;;
    esac
    ok "OS=$OS  PM=$PM"

    # ---------- 1. Node.js >= 18 ----------
    step "检测 Node.js (要求 >= 18)"
    NODE_OK=0
    if command -v node >/dev/null 2>&1; then
        NV=$(node --version 2>/dev/null || true)
        MAJ=$(printf '%s' "$NV" | sed -E 's/^v([0-9]+).*/\1/')
        if [ -n "$MAJ" ] && [ "$MAJ" -ge 18 ]; then
            ok "Node.js $NV 已就绪"; NODE_OK=1
        else
            warn "Node.js $NV 版本过低, 需要升级"
        fi
    else
        warn "未检测到 node 命令"
    fi

    # 通用回退: 下 Node.js 官方 linux-x64 tarball, 装到 /usr/local
    # 适用于 NodeSource 不支持的发行版 (TencentOS / openEuler / Alibaba Cloud Linux 等)
    # 镜像策略对齐敲敲云 install.sh: Tencent Cloud (国内主推) → 华为云 → 清华
    install_node_tarball() {
        local ver='22.11.0'
        local tgz="node-v${ver}-linux-x64.tar.xz"
        local urls=(
            "https://mirrors.cloud.tencent.com/nodejs-release/v${ver}/${tgz}"
            "https://mirrors.huaweicloud.com/nodejs/v${ver}/${tgz}"
            "https://mirrors.tuna.tsinghua.edu.cn/nodejs-release/v${ver}/${tgz}"
        )
        if ! command -v xz >/dev/null 2>&1; then
            case "$PM" in
                apt)     _sudo apt-get install -y xz-utils ;;
                dnf|yum) _sudo "$PM" install -y xz ;;
                pacman)  _sudo pacman -Sy --noconfirm xz ;;
                zypper)  _sudo zypper install -y xz ;;
                apk)     _sudo apk add --no-cache xz ;;
            esac
        fi
        local ok_url=''
        for url in "${urls[@]}"; do
            echo "  尝试镜像: $url"
            if curl -fsSL --connect-timeout 10 "$url" -o "/tmp/${tgz}" 2>/dev/null \
               && [ -s "/tmp/${tgz}" ]; then
                ok_url="$url"; break
            fi
            rm -f "/tmp/${tgz}"
        done
        [ -n "$ok_url" ] || die "Node.js tarball 三个镜像源都下载失败"
        echo "  下载成功: $ok_url"
        _sudo tar -xJf "/tmp/${tgz}" -C /usr/local --strip-components=1
        rm -f "/tmp/${tgz}"
    }

    _node_ver_ok() {
        local maj
        maj=$(node --version 2>/dev/null | sed -E 's/^v([0-9]+).*/\1/')
        [ -n "$maj" ] && [ "$maj" -ge 18 ]
    }

    if [ "$NODE_OK" -eq 0 ]; then
        step "安装 Node.js LTS"
        case "$PM" in
            brew)
                brew install node
                ;;
            apt)
                _sudo apt-get update
                _sudo apt-get install -y curl ca-certificates
                # 先试系统仓库 (Ubuntu 24.04+ 默认带 18+)
                _sudo apt-get install -y nodejs npm 2>/dev/null || true
                if ! _node_ver_ok; then
                    warn "系统仓库 Node.js 版本不够, 改用 NodeSource setup_lts"
                    _sudo apt-get remove -y nodejs npm 2>/dev/null || true
                    if curl -fsSL https://deb.nodesource.com/setup_lts.x -o /tmp/ns_setup.sh \
                       && _sudo bash /tmp/ns_setup.sh; then
                        _sudo apt-get install -y nodejs
                    fi
                    rm -f /tmp/ns_setup.sh
                fi
                if ! _node_ver_ok; then
                    warn "NodeSource 也失败, 回退官方 tarball"
                    install_node_tarball
                fi
                ;;
            dnf|yum)
                # 先试系统仓库 (TencentOS 4 / RHEL 9 / Rocky 9 自带 18 或 20)
                _sudo "$PM" install -y nodejs 2>/dev/null || true
                if ! _node_ver_ok; then
                    warn "系统仓库 Node.js 不可用或版本过低, 回退 Node.js 官方 tarball"
                    _sudo "$PM" remove -y nodejs 2>/dev/null || true
                    install_node_tarball
                fi
                ;;
            pacman) _sudo pacman -Sy --noconfirm nodejs npm ;;
            zypper) _sudo zypper install -y nodejs npm ;;
            apk)    _sudo apk add --no-cache nodejs npm ;;
        esac
        command -v node >/dev/null 2>&1 || die "Node.js 安装后仍找不到 node 命令"
        _node_ver_ok || die "Node.js 安装后版本仍 < 18: $(node --version)"
        ok "Node.js $(node --version)"
    fi

    # ---------- 2. Python 3.12+ ----------
    # 强制 3.12+ (与 Windows 版 install-claude-code.ps1 对齐, 老版本 3.6/3.8 都不收)
    # 终极兜底: Miniconda (Tencent Cloud / Tsinghua / 官方, 保证拿到 3.12)
    step "检测 Python (要求 >= 3.12)"
    PY_OK=0
    PY_CMD=''
    _py_ok() {
        local pv="$1"
        # 只接受 Python 3.12+ (3.12/3.13/.../3.99 + 4.x 全 OK; 3.11 及以下拒绝)
        printf '%s' "$pv" | grep -Eq 'Python (3\.(1[2-9]|[2-9][0-9])|[4-9]\.)'
    }
    _scan_python() {
        local c
        # 只扫 3.12+ 命名; python3/python 也试 (新系统软链可能已是 3.12+)
        for c in python3.13 python3.12 python3 python; do
            if command -v "$c" >/dev/null 2>&1; then
                local pv
                pv=$("$c" --version 2>&1 || true)
                if _py_ok "$pv"; then
                    PY_OK=1; PY_CMD="$c"; ok "$c -> $pv"
                    return 0
                fi
            fi
        done
        return 1
    }

    # Miniconda 兜底: 镜像策略对齐 install.sh 用的 Tencent Cloud / Tsinghua
    install_python_miniconda() {
        warn "系统仓库无 Python 3.12+ (典型如 CentOS 8 默认 3.6 / Ubuntu 22.04 默认 3.10), 改用 Miniconda 装 3.12"
        local installer=/tmp/miniconda.sh
        local urls=(
            'https://mirrors.cloud.tencent.com/anaconda/miniconda/Miniconda3-latest-Linux-x86_64.sh'
            'https://mirrors.tuna.tsinghua.edu.cn/anaconda/miniconda/Miniconda3-latest-Linux-x86_64.sh'
            'https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh'
        )
        local mc_path=/opt/miniconda3
        local ok_url=''
        for url in "${urls[@]}"; do
            echo "  尝试镜像: $url"
            if curl -fsSL --connect-timeout 10 "$url" -o "$installer" 2>/dev/null \
               && [ -s "$installer" ]; then
                ok_url="$url"; break
            fi
            rm -f "$installer"
        done
        [ -n "$ok_url" ] || die "Miniconda 全部镜像下载失败"
        echo "  下载成功 ($(du -h "$installer" | cut -f1)), 静默安装到 $mc_path ..."
        _sudo bash "$installer" -b -p "$mc_path"
        rm -f "$installer"

        # 暴露成系统命令 (装到 /usr/local/bin, 在默认 PATH 中)
        _sudo ln -sf "$mc_path/bin/python3"     /usr/local/bin/python3.12
        _sudo ln -sf "$mc_path/bin/pip3"        /usr/local/bin/pip3.12
        ok "Miniconda 安装完成, Python 3.12 可用: /usr/local/bin/python3.12"
    }

    # 初次扫描
    _scan_python || true

    if [ "$PY_OK" -eq 0 ]; then
        step "安装 Python 3.12 (优先系统仓库, 兜底 Miniconda)"
        case "$PM" in
            brew)
                brew install python@3.12
                brew link --force --overwrite python@3.12 2>/dev/null || true
                ;;
            apt)
                # Ubuntu 24.04+ 系统仓库有 python3.12; 22.04/20.04 需 deadsnakes PPA
                _sudo apt-get install -y python3.12 python3.12-venv 2>/dev/null || true
                if ! _scan_python 2>/dev/null; then
                    warn "系统仓库无 python3.12, 尝试 deadsnakes PPA"
                    _sudo apt-get install -y software-properties-common 2>/dev/null \
                        && _sudo add-apt-repository -y ppa:deadsnakes/ppa 2>/dev/null \
                        && _sudo apt-get update \
                        && _sudo apt-get install -y python3.12 python3.12-venv 2>/dev/null \
                        || true
                fi
                ;;
            dnf|yum)
                # Fedora / RHEL 9+ / Rocky 9+ 都有 python3.12; RHEL 8 / CentOS 7 走 miniconda 兜底
                _sudo "$PM" install -y python3.12 2>/dev/null || true
                ;;
            pacman) _sudo pacman -Sy --noconfirm python ;;
            zypper) _sudo zypper install -y python312 2>/dev/null || true ;;
            apk)    _sudo apk add --no-cache python3 ;;
        esac

        # 再次扫描
        _scan_python || true

        # 终极兜底: Miniconda (任何 PM 装不出 3.12 都走这里)
        if [ "$PY_OK" -eq 0 ]; then
            install_python_miniconda
            _scan_python || die "Miniconda 安装后仍无法找到可用 Python 3.12+"
        fi
    fi

    # 最终再确认一次版本 (扫描时已校验, 这里只为防御性兜底)
    if [ -n "$PY_CMD" ]; then
        PV=$("$PY_CMD" --version 2>&1 || true)
        _py_ok "$PV" || die "Python 版本不达标 ($PV), 要求 >= 3.12"
        ok "Python 最终版本: $PV"

        # 让 python3 / python 命令也指向 3.12+ (通过 /usr/local/bin 软链)
        # /usr/local/bin 在 PATH 中优先于 /usr/bin, 交互 shell 中 python3 → 3.12 立即生效
        # 系统工具 (yum/dnf 等) 用 #!/usr/libexec/platform-python 绝对路径, 不受影响
        # 若 PY_CMD 本身就是 python3/python, 说明系统默认已是 3.12+, 不需要再造软链
        if [ "$OS" = "linux" ] && [ "$PY_CMD" != "python3" ] && [ "$PY_CMD" != "python" ]; then
            PY_ABS=$(command -v "$PY_CMD" 2>/dev/null || true)
            if [ -n "$PY_ABS" ]; then
                _sudo ln -sf "$PY_ABS" /usr/local/bin/python3 2>/dev/null || true
                _sudo ln -sf "$PY_ABS" /usr/local/bin/python  2>/dev/null || true
                ok "已让 python3 / python 命令指向 3.12+: $PY_ABS"
            fi
        fi
    fi

    # ---------- 3. Git ----------
    step "检测 Git"
    GIT_OK=0
    if command -v git >/dev/null 2>&1; then
        GV=$(git --version 2>/dev/null || true)
        if [ -n "$GV" ]; then ok "Git 已就绪: $GV"; GIT_OK=1; fi
    else
        warn "未检测到 git 命令"
    fi
    if [ "$GIT_OK" -eq 0 ]; then
        step "安装 Git"
        case "$PM" in
            brew)    brew install git ;;
            apt)     _sudo apt-get install -y git ;;
            dnf|yum) _sudo "$PM" install -y git ;;
            pacman)  _sudo pacman -Sy --noconfirm git ;;
            zypper)  _sudo zypper install -y git ;;
            apk)     _sudo apk add --no-cache git ;;
        esac
        command -v git >/dev/null 2>&1 || die "Git 安装后仍找不到 git 命令"
        ok "Git $(git --version)"
    fi

    # ---------- 4. npm 配置 (用户级 prefix, 免 sudo) ----------
    step "配置 npm (用户级 prefix + 国内镜像)"
    NPM_PREFIX="$HOME/.npm-global"
    mkdir -p "$NPM_PREFIX"
    npm config set prefix "$NPM_PREFIX"
    case ":$PATH:" in
        *":$NPM_PREFIX/bin:"*) ;;
        *) export PATH="$NPM_PREFIX/bin:$PATH" ;;
    esac
    ok "npm prefix = $NPM_PREFIX  (无需 sudo)"

    if [ "$NO_MIRROR" -eq 0 ]; then
        npm config set registry https://registry.npmmirror.com
        ok "registry = $(npm config get registry)"
    else
        warn "已通过 --no-mirror 跳过 npm 镜像配置"
    fi

    # ---------- 5. Claude Code ----------
    step "安装 Claude Code (@anthropic-ai/claude-code)"
    EXISTING=''
    if command -v claude >/dev/null 2>&1; then
        EXISTING=$(claude --version 2>/dev/null || true)
    fi
    if [ -n "$EXISTING" ] && [ "$FORCE" -eq 0 ]; then
        ok "已安装: $EXISTING  (重装请使用 --force)"
    else
        [ -n "$EXISTING" ] && echo "  强制重装 (原版本: $EXISTING)"
        npm install -g @anthropic-ai/claude-code
        hash -r 2>/dev/null || true
        command -v claude >/dev/null 2>&1 \
            || die "claude 命令安装后仍不可用 (检查 PATH 是否包含 $NPM_PREFIX/bin)"
        ok "Claude Code $(claude --version)"
    fi

    # ---------- 6. 写入 shell rc ----------
    step "写入 shell 配置"

    TARGETS=()
    [ -f "$HOME/.zshrc" ]        && TARGETS+=("$HOME/.zshrc")
    [ -f "$HOME/.bashrc" ]       && TARGETS+=("$HOME/.bashrc")
    [ -f "$HOME/.bash_profile" ] && TARGETS+=("$HOME/.bash_profile")
    [ -f "$HOME/.profile" ]      && TARGETS+=("$HOME/.profile")
    if [ "${#TARGETS[@]}" -eq 0 ]; then
        case "${SHELL:-}" in
            */zsh)  TARGETS=("$HOME/.zshrc");  touch "$HOME/.zshrc" ;;
            */bash) TARGETS=("$HOME/.bashrc"); touch "$HOME/.bashrc" ;;
            *)      TARGETS=("$HOME/.profile"); touch "$HOME/.profile" ;;
        esac
    fi

    BEGIN_MARK='# >>> claude-code deepseek (managed by install-claude-code.sh) >>>'
    END_MARK='# <<< claude-code deepseek (managed by install-claude-code.sh) <<<'

    BLOCK=$(cat <<EOF
$BEGIN_MARK
export ANTHROPIC_BASE_URL="https://api.deepseek.com/anthropic"
export ANTHROPIC_MODEL="$MODEL"
export ANTHROPIC_SMALL_FAST_MODEL="$MODEL"
export PATH="$NPM_PREFIX/bin:\$PATH"
$END_MARK
EOF
)

    for f in "${TARGETS[@]}"; do
        if grep -qF "$BEGIN_MARK" "$f" 2>/dev/null; then
            tmp=$(mktemp)
            awk -v b="$BEGIN_MARK" -v e="$END_MARK" '
                $0==b {skip=1; next}
                $0==e {skip=0; next}
                !skip {print}
            ' "$f" > "$tmp" && mv "$tmp" "$f"
        fi
        printf '\n%s\n' "$BLOCK" >> "$f"
        ok "已更新 $f"
    done

    # 当前会话立即生效
    export ANTHROPIC_BASE_URL="https://api.deepseek.com/anthropic"
    export ANTHROPIC_MODEL="$MODEL"
    export ANTHROPIC_SMALL_FAST_MODEL="$MODEL"

    # ---------- 9. 完成 ----------
    printf '\n%s============================================================%s\n' "$GREEN" "$NC"
    printf '%s  🎉  安装全部完成 !%s\n'                                            "$GREEN" "$NC"
    printf '%s============================================================%s\n\n' "$GREEN" "$NC"
    cat <<EOF
  ┌─ 已安装组件 ───────────────────────────────────────────
  │   Node.js      : $(node --version)
  │   Python       : $($PY_CMD --version 2>&1)
  │   Git          : $(git --version)
  │   Claude Code  : $(claude --version 2>/dev/null)
  └────────────────────────────────────────────────────────

  ┌─ DeepSeek 接入配置 (已写入 shell rc) ──────────────────
  │   模型         : $MODEL
  │   接口地址     : https://api.deepseek.com/anthropic
  │   API Key      : $(mask "$API_KEY")
  └────────────────────────────────────────────────────────

  🔧 常用命令
    claude --version          查看版本
    claude --help             查看全部参数
    claude /config            进入设置 (改模型/Key 等)
    claude /clear             清空当前对话上下文

  💡 提示
    • DeepSeek 按 token 计费, 用前确认账户余额 (platform.deepseek.com)
    • 重装 / 换 Key       : bash install-claude-code.sh --force
    • 卸载 Claude Code    : npm uninstall -g @anthropic-ai/claude-code

EOF

    # ===== 最大字体: 把"必须做的下一步"放到所有输出最后, 颜色最显眼 =====
    printf '\n%s' "$YELLOW"
    cat <<EOF
╔══════════════════════════════════════════════════════════╗
║  ⚠️  当前 shell 的 PATH 还没刷新, 不能直接跑 claude !    ║
║                                                          ║
║  请复制下面这一行执行, 立即激活并启动 claude:            ║
║                                                          ║
║      source ${TARGETS[0]} && claude
║                                                          ║
║  (或者直接重开一个 SSH 会话, 新 shell 会自动生效)        ║
╚══════════════════════════════════════════════════════════╝
EOF
    printf '%s\n' "$NC"
}

_main "$@"

#!/bin/bash

# ==========================================
# OpenClaw (Moltbot) 智能体一键部署脚本
# 适用平台: Linux / macOS / WSL
# 版本: 2.0.1 (适配 2026 最新架构)
# ==========================================

# --- 0. 初始化配置与美化 ---
# 设置严格模式：遇到错误退出，管道失败退出
set -euo pipefail

# 定义颜色代码，用于提升交互体验
RED='\033${NC} $1"; }
log_success() { echo -e "${GREEN}[成功]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[注意]${NC} $1"; }
log_error() { echo -e "${RED}[错误]${NC} $1"; }
log_step() { echo -e "\n${CYAN}>>> 步骤: $1${NC}"; }

# 清屏并显示欢迎 Banner
clear
echo -e "${CYAN}"
echo "╔════════════════════════════════════════════════════════════╗"
echo "║          OpenClaw 个人 AI 智能体一键部署助手               ║"
echo "║             (Linux / macOS / WSL 专用版)                   ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo "正在初始化安装程序..."
sleep 1

# --- 1. 环境预检 (Pre-flight Checks) ---
log_step "检查系统环境"

# 检查 Docker 是否安装
if! command -v docker &> /dev/null; then
    log_error "未检测到 Docker！"
    echo "OpenClaw 依赖 Docker 运行。请访问以下链接安装："
    echo "👉 https://docs.docker.com/get-docker/"
    exit 1
fi

# 检查 Docker 守护进程是否运行
if! docker info &> /dev/null; then
    log_error "Docker 服务未启动！"
    echo "请启动 Docker Desktop 或在终端运行 'sudo systemctl start docker'。"
    exit 1
fi

# 检查 docker compose 命令
if! docker compose version &> /dev/null; then
    log_warn "未检测到 'docker compose' 插件，尝试使用旧版 'docker-compose'..."
    if! command -v docker-compose &> /dev/null; then
        log_error "无法找到 Docker Compose。请更新您的 Docker 版本。"
        exit 1
    fi
    DOCKER_COMPOSE_CMD="docker-compose"
else
    DOCKER_COMPOSE_CMD="docker compose"
fi

log_success "环境检查通过！使用编排命令: $DOCKER_COMPOSE_CMD"

# --- 2. 交互式参数配置 ---
log_step "配置部署参数"

# 获取当前用户主目录
DEFAULT_DIR="$HOME/.openclaw"

echo -e "我们将把 OpenClaw 安装在您的用户目录下。"
read -p "请输入安装路径 (直接回车默认: $DEFAULT_DIR): " INPUT_DIR
INSTALL_DIR=${INPUT_DIR:-$DEFAULT_DIR}

DEFAULT_PORT="18789"
read -p "请输入 Web 控制台端口 (直接回车默认: $DEFAULT_PORT): " INPUT_PORT
PORT=${INPUT_PORT:-$DEFAULT_PORT}

echo ""
log_info "安装目标: $INSTALL_DIR"
log_info "服务端口: $PORT"
log_info "镜像来源: ghcr.io/openclaw/openclaw:latest"

echo ""
read -p "确认以上信息无误？按 Enter 开始部署，按 Ctrl+C 取消..."

# --- 3. 目录与权限设置 ---
log_step "创建文件结构"

# 创建主目录、配置目录和工作区
mkdir -p "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR/config"
mkdir -p "$INSTALL_DIR/workspace"

# 赋予当前用户对目录的完整权限，防止 Docker 容器内权限不足
# 注意：在 Linux 下，容器内默认用户 node (uid 1000) 需要写入权限
if]; then
    chmod 755 "$INSTALL_DIR/config"
    chmod 755 "$INSTALL_DIR/workspace"
fi

log_success "目录结构已就绪。"

# --- 4. 生成配置文件 (Infrastructure as Code) ---
log_step "生成 Docker 配置文件"

# 自动生成安全令牌 (Gateway Token)
# 优先使用 openssl 生成强随机数，降级使用 python，最后使用 date 哈希
if command -v openssl &> /dev/null; then
    GATEWAY_TOKEN=$(openssl rand -hex 32)
elif command -v python3 &> /dev/null; then
    GATEWAY_TOKEN=$(python3 -c "import secrets; print(secrets.token_hex(32))")
else
    GATEWAY_TOKEN=$(date +%s%N | sha256sum | head -c 64)
fi

# 动态写入 docker-compose.yml
# 使用 EOF 块写入，确保变量被正确解析
cat > "$INSTALL_DIR/docker-compose.yml" <<EOF
services:
  openclaw-gateway:
    # 使用最新的官方镜像 ghcr.io/openclaw/openclaw
    image: ghcr.io/openclaw/openclaw:latest
    container_name: openclaw-gateway
    restart: unless-stopped
    # 网络模式：桥接
    ports:
      - "${PORT}:18789"
    volumes:
      # 挂载配置目录
      -./config:/home/node/.openclaw
      # 挂载工作区 (AI 可读写区域)
      -./workspace:/home/node/.openclaw/workspace
    environment:
      - NODE_ENV=production
      # 设置安全访问令牌
      - OPENCLAW_GATEWAY_TOKEN=${GATEWAY_TOKEN}
      # 允许首次启动时未配置状态，方便进入向导
      - OPENCLAW_ALLOW_UNCONFIGURED=true
      # 绑定地址，允许 Docker 外部访问
      - OPENCLAW_GATEWAY_BIND=0.0.0.0
    healthcheck:
      test:
      interval: 30s
      timeout: 10s
      retries: 3
    command: ["gateway"]

EOF

log_success "docker-compose.yml 生成完毕。"
log_info "已生成随机访问令牌 (Token)。"

# --- 5. 服务部署与启动 ---
log_step "拉取镜像并启动服务"
echo "正在从 GitHub Container Registry 下载镜像，请耐心等待..."

cd "$INSTALL_DIR"

# 拉取最新镜像
if! $DOCKER_COMPOSE_CMD pull; then
    log_error "镜像拉取失败！"
    echo "常见原因：网络无法访问 ghcr.io。请检查您的网络连接或代理设置。"
    exit 1
fi

# 启动容器
if! $DOCKER_COMPOSE_CMD up -d; then
    log_error "容器启动失败！"
    echo "请检查端口 $PORT 是否被占用。"
    exit 1
fi

# --- 6. 最终验证与引导 ---
log_step "验证部署状态"
sleep 5 # 等待几秒让服务初始化

if $DOCKER_COMPOSE_CMD ps | grep "openclaw-gateway" | grep -q "Up"; then
    log_success "OpenClaw 智能体已成功上线！"
else
    log_warn "服务状态异常，请稍后运行 'docker compose logs' 检查日志。"
fi

# --- 7. 结束页与操作指引 ---
echo -e "${CYAN}"
echo "════════════════════════════════════════════════════════════"
echo " 🎉 部署成功！您可以开始使用了"
echo "════════════════════════════════════════════════════════════"
echo -e "${NC}"
echo -e "1. 🌐 访问地址 (浏览器):   ${GREEN}http://localhost:${PORT}${NC}"
echo -e "2. 🔑 登录令牌 (Token):    ${YELLOW}${GATEWAY_TOKEN}${NC}"
echo -e "   (请妥善保管此令牌，它是您控制 AI 的唯一凭证)"
echo ""
echo -e "📂 数据目录: ${INSTALL_DIR}"
echo -e "🛠️  查看日志: cd ${INSTALL_DIR} && $DOCKER_COMPOSE_CMD logs -f"
echo -e "🛑 停止服务: cd ${INSTALL_DIR} && $DOCKER_COMPOSE_CMD down"
echo ""
echo -e "${CYAN}下一步建议：${NC}"
echo "打开浏览器访问上述地址，输入令牌，然后配置您的 AI 模型提供商（如 Anthropic 或 OpenAI）。"
echo ""

<#
.SYNOPSIS
    OpenClaw (Moltbot) Windows 一键部署自动化脚本
.DESCRIPTION
    该脚本旨在为 Windows 用户提供“小白化”的 OpenClaw 部署体验。
    自动检测 Docker Desktop，生成配置，处理编码问题，并启动服务。
.NOTES
    需要管理员权限运行 PowerShell。
    作者: OpenClaw Research Report
#>

# --- 0. 初始化与权限检查 ---
$ErrorActionPreference = "Stop" # 遇到错误立即停止

# 设置控制台输出编码为 UTF-8，防止中文乱码显示
[Console]::OutputEncoding =::UTF8

# 颜色输出辅助函数
function Write-Info ($msg) { Write-Host "[信息] $msg" -ForegroundColor Cyan }
function Write-Success ($msg) { Write-Host "[成功] $msg" -ForegroundColor Green }
function Write-Warn ($msg) { Write-Host "[注意] $msg" -ForegroundColor Yellow }
function Write-ErrorMsg ($msg) { Write-Host "[错误] $msg" -ForegroundColor Red }

# 检查是否以管理员身份运行
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal(::GetCurrent())
if (-not $currentPrincipal.IsInRole(::Administrator)) {
    Write-ErrorMsg "请以管理员身份运行此脚本！"
    Write-Host "👉 方法：右键点击 PowerShell 图标，选择“以管理员身份运行”。"
    exit 1
}

# 显示欢迎界面
Clear-Host
Write-Host "╔════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║          OpenClaw Windows 一键部署助手                     ║" -ForegroundColor Cyan
Write-Host "║        (支持 Windows 10/11 + Docker Desktop)               ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""
Write-Host "正在初始化安装程序..." 
Start-Sleep -Seconds 1

# --- 1. 环境预检 ---
Write-Host "`n>>> 步骤 1: 检查系统环境" -ForegroundColor Yellow

# 检查 Docker 命令
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-ErrorMsg "未检测到 Docker！"
    Write-Host "OpenClaw 需要 Docker Desktop 才能在 Windows 上运行。"
    Write-Host "请前往官网下载安装: https://www.docker.com/products/docker-desktop/"
    exit 1
}

# 检查 Docker 服务状态
try {
    $dockerInfo = docker info 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Docker 未响应" }
    Write-Success "Docker 环境检查通过。"
} catch {
    Write-ErrorMsg "Docker 服务似乎未启动。"
    Write-Host "请先启动 'Docker Desktop' 应用程序，等待其图标停止闪烁后再重试。"
    exit 1
}

# --- 2. 参数配置 ---
Write-Host "`n>>> 步骤 2: 配置部署选项" -ForegroundColor Yellow

# 设置默认安装路径 (用户主目录/.openclaw)
$UserProfile = $env:USERPROFILE
$DefaultDir = Join-Path $UserProfile ".openclaw"

Write-Host "我们将把 OpenClaw 安装在: $DefaultDir"
$inputDir = Read-Host "按 Enter 使用默认路径，或输入自定义路径"
if ([string]::IsNullOrWhiteSpace($inputDir)) {
    $InstallDir = $DefaultDir
} else {
    $InstallDir = $inputDir
}

# 设置端口
$DefaultPort = "18789"
$inputPort = Read-Host "请输入 Web 端口 (默认: $DefaultPort)"
if ([string]::IsNullOrWhiteSpace($inputPort)) {
    $Port = $DefaultPort
} else {
    $Port = $inputPort
}

Write-Info "安装目录: $InstallDir"
Write-Info "Web 端口: $Port"
Write-Host ""

# --- 3. 目录创建 ---
Write-Host "`n>>> 步骤 3: 创建目录结构" -ForegroundColor Yellow

if (-not (Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
}
# 创建 config 和 workspace 子目录
$ConfigDir = Join-Path $InstallDir "config"
$WorkspaceDir = Join-Path $InstallDir "workspace"

if (-not (Test-Path $ConfigDir)) { New-Item -ItemType Directory -Force -Path $ConfigDir | Out-Null }
if (-not (Test-Path $WorkspaceDir)) { New-Item -ItemType Directory -Force -Path $WorkspaceDir | Out-Null }

Write-Success "目录结构创建完成。"

# --- 4. 生成配置文件 ---
Write-Host "`n>>> 步骤 4: 生成配置文件" -ForegroundColor Yellow

# 生成 64 字符的随机 Token (使用.NET 加密库)
try {
    $TokenBytes = New-Object byte 32
    $Random =::Create()
    $Random.GetBytes($TokenBytes)
    $GatewayToken = -join ($TokenBytes | ForEach-Object { $_.ToString("x2") })
} catch {
    $GatewayToken = -join ((1..64) | ForEach-Object { Get-Random -Minimum 0 -Maximum 16 | ForEach-Object { $_.ToString("x") } })
}

# 定义 docker-compose.yml 内容
# 注意：在 Windows 中，volumes 路径通常建议使用相对路径，Docker Desktop 会自动处理转换
$DockerComposeContent = @"
services:
  openclaw-gateway:
    image: ghcr.io/openclaw/openclaw:latest
    container_name: openclaw-gateway
    restart: unless-stopped
    ports:
      - "${Port}:18789"
    volumes:
      -./config:/home/node/.openclaw
      -./workspace:/home/node/.openclaw/workspace
    environment:
      - NODE_ENV=production
      - OPENCLAW_GATEWAY_TOKEN=${GatewayToken}
      - OPENCLAW_ALLOW_UNCONFIGURED=true
    command: ["gateway"]
"@

# 写入文件，强制使用 UTF8 无 BOM 格式，避免 Docker 解析错误
$ComposePath = Join-Path $InstallDir "docker-compose.yml"
::WriteAllText($ComposePath, $DockerComposeContent,::UTF8)

Write-Success "配置文件已生成。"
Write-Info "Token 已生成: $GatewayToken"

# --- 5. 启动服务 ---
Write-Host "`n>>> 步骤 5: 拉取镜像并启动" -ForegroundColor Yellow
Write-Host "首次运行需要下载镜像，可能需要几分钟，请不要关闭窗口..." -ForegroundColor Gray

# 切换工作目录
Set-Location -Path $InstallDir

try {
    docker compose pull
    docker compose up -d
} catch {
    Write-ErrorMsg "启动失败！"
    Write-Host "可能原因: 网络问题或端口被占用。"
    Write-Host "详细错误: $_"
    exit 1
}

# --- 6. 完成引导 ---
Start-Sleep -Seconds 5
# 检查容器状态
$Running = docker compose ps | Select-String "openclaw-gateway"

if ($Running) {
    Write-Host "`n════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host " 🎉 部署完成！" -ForegroundColor Cyan
    Write-Host "════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "🌐 访问地址: http://localhost:${Port}" -ForegroundColor Green
    Write-Host "🔑 访问令牌: ${GatewayToken}" -ForegroundColor Yellow
    Write-Host "   (请复制上方令牌，用于登录控制台)"
    Write-Host ""
    Write-Host "📂 数据目录: $InstallDir"
    Write-Host "📝 查看日志: cd $InstallDir ; docker compose logs -f"
    Write-Host ""
    
    $OpenWeb = Read-Host "是否现在打开浏览器? (Y/N)"
    if ($OpenWeb -eq 'Y' -or $OpenWeb -eq 'y') {
        Start-Process "http://localhost:${Port}"
    }
} else {
    Write-ErrorMsg "服务启动状态异常。"
    Write-Host "请运行 'docker compose logs' 查看错误详情。"
}

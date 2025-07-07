#!/bin/bash

# 深度404故障分析脚本
# 分析FastPanel + Cloudflare环境中被忽略的故障点

set -e

echo "🔬 深度404故障分析"
echo "===================="
echo "分析FastPanel + Cloudflare环境中可能被忽略的故障原因"
echo ""

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✅]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[⚠️]${NC} $1"
}

log_error() {
    echo -e "${RED}[❌]${NC} $1"
}

log_critical() {
    echo -e "${RED}[🚨 CRITICAL]${NC} $1"
}

PROJECT_DIR="/var/www/besthammer_c_usr/data/www/besthammer.club"
PUBLIC_DIR="$PROJECT_DIR/public"

echo "🔍 1. FastPanel进程和服务分析"
echo "================================"

# 检查FastPanel特有的服务
log_info "检查FastPanel相关进程..."
if pgrep -f "fastpanel" > /dev/null; then
    log_success "FastPanel进程运行中"
    ps aux | grep fastpanel | grep -v grep
else
    log_warning "未发现FastPanel进程"
fi

# 检查PHP-FPM状态
log_info "检查PHP-FPM服务..."
if systemctl is-active --quiet php*-fpm; then
    log_success "PHP-FPM服务运行中"
    systemctl status php*-fpm --no-pager -l | head -5
else
    log_error "PHP-FPM服务未运行"
fi

# 检查Nginx（FastPanel可能使用Nginx作为前端代理）
log_info "检查Nginx服务..."
if systemctl is-active --quiet nginx; then
    log_warning "发现Nginx服务运行 - 这可能是问题所在！"
    echo "   Nginx可能在Apache前面作为代理"
    nginx -t 2>&1 | head -3
else
    log_info "Nginx未运行"
fi

echo ""
echo "🌐 2. 网络层面深度分析"
echo "========================"

# 检查端口占用
log_info "检查端口80和443的占用情况..."
echo "端口80占用："
netstat -tlnp | grep ":80 " || echo "   端口80未被占用"
echo "端口443占用："
netstat -tlnp | grep ":443 " || echo "   端口443未被占用"

# 检查防火墙
log_info "检查防火墙状态..."
if command -v ufw &> /dev/null; then
    ufw status
elif command -v iptables &> /dev/null; then
    iptables -L INPUT | head -5
fi

# 检查本地连接
log_info "测试本地连接..."
echo "本地HTTP测试："
curl -I -H "Host: www.besthammer.club" http://localhost 2>/dev/null | head -3 || echo "   本地HTTP连接失败"

echo "本地HTTPS测试："
curl -I -k -H "Host: www.besthammer.club" https://localhost 2>/dev/null | head -3 || echo "   本地HTTPS连接失败"

echo ""
echo "📁 3. 文件系统深度检查"
echo "======================"

# 检查挂载点
log_info "检查文件系统挂载..."
df -h | grep -E "(www|besthammer)" || echo "   未发现相关挂载点"

# 检查文件系统权限
log_info "检查关键目录权限..."
if [ -d "$PROJECT_DIR" ]; then
    ls -la "$PROJECT_DIR" | head -5
    echo ""
    echo "Public目录详情："
    ls -la "$PUBLIC_DIR" | head -10
else
    log_error "项目目录不存在"
fi

# 检查SELinux
log_info "检查SELinux状态..."
if command -v getenforce &> /dev/null; then
    SELINUX_STATUS=$(getenforce)
    echo "   SELinux状态: $SELINUX_STATUS"
    if [ "$SELINUX_STATUS" = "Enforcing" ]; then
        log_warning "SELinux处于强制模式，可能阻止访问"
    fi
else
    echo "   SELinux未安装"
fi

echo ""
echo "🔧 4. Apache配置深度分析"
echo "========================"

# 检查Apache配置文件
log_info "分析Apache主配置..."
apache2ctl -S 2>&1 | head -10

# 检查所有启用的站点
log_info "检查所有启用的虚拟主机..."
echo "启用的站点："
ls -la /etc/apache2/sites-enabled/

echo ""
echo "虚拟主机配置摘要："
for site in /etc/apache2/sites-enabled/*; do
    if [ -f "$site" ]; then
        echo "=== $(basename $site) ==="
        grep -E "(ServerName|DocumentRoot|VirtualHost)" "$site" | head -5
        echo ""
    fi
done

# 检查Apache错误日志的详细信息
log_info "分析Apache错误日志..."
if [ -f "/var/log/apache2/error.log" ]; then
    echo "最近的Apache错误（详细）："
    tail -n 10 /var/log/apache2/error.log | grep -E "(error|404|besthammer)" || echo "   未发现相关错误"
fi

echo ""
echo "☁️ 5. Cloudflare连接深度分析"
echo "============================"

# 获取服务器真实IP
SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || curl -s ipinfo.io/ip 2>/dev/null || echo "未知")
log_info "服务器真实IP: $SERVER_IP"

# 测试直接IP访问
log_info "测试直接IP访问..."
echo "直接访问服务器IP:"
curl -I -H "Host: www.besthammer.club" "http://$SERVER_IP" 2>/dev/null | head -3 || echo "   直接IP访问失败"

# 检查DNS解析路径
log_info "追踪DNS解析路径..."
if command -v dig &> /dev/null; then
    echo "DNS解析详情："
    dig +short www.besthammer.club
    echo "DNS解析路径："
    dig +trace www.besthammer.club | tail -5
else
    echo "dig命令不可用，使用nslookup："
    nslookup www.besthammer.club | tail -5
fi

echo ""
echo "🚨 6. FastPanel特有问题检查"
echo "=========================="

# 检查FastPanel配置目录
FASTPANEL_DIRS=(
    "/usr/local/fastpanel"
    "/etc/fastpanel"
    "/opt/fastpanel"
    "/var/lib/fastpanel"
)

log_info "查找FastPanel配置目录..."
for dir in "${FASTPANEL_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        log_success "发现FastPanel目录: $dir"
        ls -la "$dir" | head -5
    fi
done

# 检查FastPanel用户配置
log_info "检查FastPanel用户配置..."
if id "besthammer_c_usr" &>/dev/null; then
    log_success "FastPanel用户存在"
    id besthammer_c_usr
else
    log_error "FastPanel用户不存在"
fi

# 检查FastPanel数据库
log_info "检查FastPanel数据库连接..."
if command -v mysql &> /dev/null; then
    mysql -u root -e "SHOW DATABASES;" 2>/dev/null | grep -E "(fastpanel|besthammer)" || echo "   未发现相关数据库"
fi

echo ""
echo "🔍 7. 可能的根本原因分析"
echo "======================="

echo "基于以上检查，可能的根本原因："
echo ""

# 分析可能的问题
if systemctl is-active --quiet nginx; then
    log_critical "发现Nginx运行 - 可能存在反向代理配置问题"
    echo "   → Nginx可能在Apache前面，需要配置Nginx虚拟主机"
    echo "   → 检查 /etc/nginx/sites-enabled/ 目录"
fi

if [ ! -f "$PUBLIC_DIR/index.php" ]; then
    log_critical "Laravel入口文件缺失"
    echo "   → 需要确保Laravel项目完整部署"
fi

if ! systemctl is-active --quiet php*-fpm; then
    log_critical "PHP-FPM服务未运行"
    echo "   → FastPanel可能依赖PHP-FPM而不是Apache模块"
fi

# 检查是否存在.htaccess问题
if [ -f "$PUBLIC_DIR/.htaccess" ]; then
    if ! grep -q "RewriteEngine On" "$PUBLIC_DIR/.htaccess"; then
        log_critical ".htaccess文件可能有问题"
        echo "   → URL重写规则可能不正确"
    fi
fi

echo ""
echo "📋 8. 建议的解决步骤"
echo "=================="

echo "根据分析结果，建议按以下优先级解决："
echo ""
echo "🥇 优先级1 - Nginx配置问题（如果Nginx在运行）"
echo "   sudo nano /etc/nginx/sites-available/besthammer.club"
echo "   配置Nginx反向代理到Apache"
echo ""
echo "🥈 优先级2 - PHP-FPM配置问题"
echo "   sudo systemctl start php8.1-fpm"
echo "   sudo systemctl enable php8.1-fpm"
echo ""
echo "🥉 优先级3 - FastPanel面板重新配置"
echo "   登录FastPanel面板重新配置域名"
echo ""
echo "🔧 优先级4 - 直接IP访问测试"
echo "   curl -H 'Host: www.besthammer.club' http://$SERVER_IP"
echo ""

echo "📞 如需进一步分析，请提供："
echo "   1. 此脚本的完整输出"
echo "   2. FastPanel面板的域名配置截图"
echo "   3. Cloudflare DNS设置截图"

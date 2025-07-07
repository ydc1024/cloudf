#!/bin/bash

# 502错误快速诊断脚本

echo "🔍 502错误快速诊断"
echo "=================="

# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
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

echo "1. 检查Nginx状态："
if systemctl is-active --quiet nginx; then
    log_success "Nginx运行正常"
else
    log_error "Nginx未运行"
fi

echo ""
echo "2. 检查PHP-FPM服务："
for version in 8.3 8.2 8.1 8.0; do
    service="php${version}-fpm"
    if systemctl is-active --quiet "$service" 2>/dev/null; then
        log_success "$service 运行正常"
        
        # 检查socket
        socket="/var/run/php/php${version}-fpm.sock"
        if [ -S "$socket" ]; then
            log_success "Socket存在: $socket"
            perms=$(stat -c '%a' "$socket" 2>/dev/null)
            owner=$(stat -c '%U:%G' "$socket" 2>/dev/null)
            echo "   权限: $perms ($owner)"
        else
            log_warning "Socket不存在: $socket"
        fi
    elif systemctl list-unit-files | grep -q "$service"; then
        log_warning "$service 存在但未运行"
    fi
done

echo ""
echo "3. 检查Nginx错误日志："
if [ -f "/var/log/nginx/error.log" ]; then
    echo "最近的502错误："
    tail -n 10 /var/log/nginx/error.log | grep -E "(502|upstream|connect|refused)" | tail -3 || echo "   未发现502相关错误"
fi

echo ""
echo "4. 检查Nginx配置："
if [ -f "/etc/nginx/sites-enabled/besthammer.club" ]; then
    log_success "站点配置存在"
    echo "FastCGI配置："
    grep -E "(fastcgi_pass|unix:)" /etc/nginx/sites-enabled/besthammer.club || echo "   未找到fastcgi_pass配置"
else
    log_error "站点配置不存在"
fi

echo ""
echo "5. 测试网站连接："
response=$(curl -s -o /dev/null -w "%{http_code}" "https://www.besthammer.club" 2>/dev/null || echo "000")
if [ "$response" = "502" ]; then
    log_error "确认502错误"
elif [ "$response" = "200" ]; then
    log_success "网站正常 (HTTP $response)"
else
    log_warning "HTTP状态码: $response"
fi

echo ""
echo "📋 502错误常见原因："
echo "1. PHP-FPM服务未运行"
echo "2. Socket文件不存在或权限错误"
echo "3. Nginx配置中socket路径错误"
echo "4. PHP-FPM配置问题"
echo ""
echo "🔧 建议修复步骤："
echo "1. 运行: sudo bash fix-502-error.sh"
echo "2. 检查修复结果"
echo "3. 测试网站访问"

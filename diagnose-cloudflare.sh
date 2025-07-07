#!/bin/bash

# Cloudflare + FastPanel 环境诊断脚本

echo "🌐 Cloudflare + FastPanel 环境诊断报告"
echo "========================================"
echo "时间: $(date)"
echo "域名: www.besthammer.club"
echo ""

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

PROJECT_DIR="/var/www/besthammer_c_usr/data/www/besthammer.club"
PUBLIC_DIR="$PROJECT_DIR/public"

echo "☁️ 1. Cloudflare连接检测"
echo "-----------------------------------"

# 检查域名是否通过Cloudflare代理
CF_CHECK=$(dig +short www.besthammer.club | head -1)
if [ -n "$CF_CHECK" ]; then
    log_info "域名解析IP: $CF_CHECK"
    
    # 检查是否为Cloudflare IP段
    if echo "$CF_CHECK" | grep -E "^(104\.(1[6-9]|2[0-7])\.|172\.6[4-9]\.|172\.7[0-9]\.|162\.15[8-9]\.|173\.245\.)" > /dev/null; then
        log_success "检测到Cloudflare代理IP"
    else
        log_warning "可能不是Cloudflare代理IP"
    fi
else
    log_error "域名解析失败"
fi

# 测试Cloudflare连接
echo ""
echo "   测试Cloudflare响应头:"
CF_HEADERS=$(curl -s -I "https://www.besthammer.club" 2>/dev/null)
if echo "$CF_HEADERS" | grep -i "cf-ray" > /dev/null; then
    log_success "检测到Cloudflare CF-Ray头"
    echo "      CF-Ray: $(echo "$CF_HEADERS" | grep -i "cf-ray" | cut -d: -f2 | tr -d ' \r')"
else
    log_warning "未检测到Cloudflare CF-Ray头"
fi

if echo "$CF_HEADERS" | grep -i "server.*cloudflare" > /dev/null; then
    log_success "检测到Cloudflare服务器头"
else
    log_warning "未检测到Cloudflare服务器头"
fi

echo ""
echo "📁 2. 项目目录结构检查"
echo "-----------------------------------"

if [ -d "$PROJECT_DIR" ]; then
    log_success "项目目录存在: $PROJECT_DIR"
else
    log_error "项目目录不存在: $PROJECT_DIR"
fi

if [ -d "$PUBLIC_DIR" ]; then
    log_success "Public目录存在: $PUBLIC_DIR"
    
    # 检查关键文件
    if [ -f "$PUBLIC_DIR/index.php" ]; then
        log_success "Laravel入口文件存在"
    else
        log_error "Laravel入口文件不存在"
    fi
    
    if [ -f "$PUBLIC_DIR/.htaccess" ]; then
        log_success ".htaccess文件存在"
    else
        log_warning ".htaccess文件不存在（可能影响URL重写）"
    fi
else
    log_error "Public目录不存在: $PUBLIC_DIR"
fi

echo ""
echo "🌐 3. Apache配置检查"
echo "-----------------------------------"

# 检查Apache状态
if systemctl is-active --quiet apache2; then
    log_success "Apache服务运行正常"
else
    log_error "Apache服务未运行"
fi

# 检查虚拟主机配置
VHOST_FILE="/etc/apache2/sites-available/besthammer.club.conf"
if [ -f "$VHOST_FILE" ]; then
    log_success "虚拟主机配置文件存在: $VHOST_FILE"
    
    # 检查DocumentRoot
    DOC_ROOT=$(grep "DocumentRoot" "$VHOST_FILE" | head -1 | awk '{print $2}')
    if [ "$DOC_ROOT" = "$PUBLIC_DIR" ]; then
        log_success "DocumentRoot配置正确: $DOC_ROOT"
    else
        log_error "DocumentRoot配置错误: $DOC_ROOT (应该是: $PUBLIC_DIR)"
    fi
else
    log_error "虚拟主机配置文件不存在: $VHOST_FILE"
fi

# 检查Cloudflare配置
if [ -f "/etc/apache2/conf-available/cloudflare.conf" ]; then
    log_success "Cloudflare配置文件存在"
    
    if apache2ctl -M | grep -q "remoteip_module"; then
        log_success "RemoteIP模块已启用"
    else
        log_error "RemoteIP模块未启用"
    fi
else
    log_warning "Cloudflare配置文件不存在"
fi

echo ""
echo "🔧 4. Apache模块检查"
echo "-----------------------------------"

REQUIRED_MODULES=("rewrite" "ssl" "headers" "remoteip")
for module in "${REQUIRED_MODULES[@]}"; do
    if apache2ctl -M | grep -q "${module}_module"; then
        log_success "模块已启用: $module"
    else
        log_error "模块未启用: $module"
    fi
done

echo ""
echo "📝 5. 日志分析"
echo "-----------------------------------"

# Apache错误日志
if [ -f "/var/log/apache2/besthammer.club_error.log" ]; then
    log_info "最近的Apache错误日志:"
    tail -n 3 /var/log/apache2/besthammer.club_error.log | sed 's/^/      /'
elif [ -f "/var/log/apache2/error.log" ]; then
    log_info "最近的Apache错误日志:"
    tail -n 3 /var/log/apache2/error.log | sed 's/^/      /'
else
    log_warning "Apache错误日志不存在"
fi

# Laravel日志
if [ -f "$PROJECT_DIR/storage/logs/laravel.log" ]; then
    log_info "最近的Laravel日志:"
    tail -n 2 "$PROJECT_DIR/storage/logs/laravel.log" | sed 's/^/      /'
else
    log_warning "Laravel日志不存在"
fi

echo ""
echo "🔐 6. SSL和HTTPS检查"
echo "-----------------------------------"

# 测试HTTP到HTTPS重定向
HTTP_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" "http://www.besthammer.club" 2>/dev/null || echo "000")
if [ "$HTTP_RESPONSE" = "301" ] || [ "$HTTP_RESPONSE" = "302" ]; then
    log_success "HTTP到HTTPS重定向正常 (HTTP $HTTP_RESPONSE)"
else
    log_warning "HTTP到HTTPS重定向异常 (HTTP $HTTP_RESPONSE)"
fi

# 测试HTTPS连接
HTTPS_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" "https://www.besthammer.club" 2>/dev/null || echo "000")
if [ "$HTTPS_RESPONSE" = "200" ]; then
    log_success "HTTPS连接正常 (HTTP $HTTPS_RESPONSE)"
elif [ "$HTTPS_RESPONSE" = "404" ]; then
    log_error "HTTPS返回404错误 - 这是主要问题！"
else
    log_warning "HTTPS连接异常 (HTTP $HTTPS_RESPONSE)"
fi

echo ""
echo "🚀 7. Laravel应用检查"
echo "-----------------------------------"

if [ -f "$PROJECT_DIR/artisan" ]; then
    log_success "Laravel artisan文件存在"
    
    cd "$PROJECT_DIR"
    
    # 检查应用密钥
    if grep -q "APP_KEY=base64:" .env 2>/dev/null; then
        log_success "应用密钥已设置"
    else
        log_error "应用密钥未设置"
    fi
    
    # 检查应用URL配置
    APP_URL=$(grep "APP_URL=" .env 2>/dev/null | cut -d= -f2)
    if [ "$APP_URL" = "https://www.besthammer.club" ]; then
        log_success "应用URL配置正确"
    else
        log_warning "应用URL配置: $APP_URL"
    fi
    
    # 检查存储目录权限
    if [ -w "storage" ]; then
        log_success "存储目录可写"
    else
        log_error "存储目录不可写"
    fi
else
    log_error "Laravel artisan文件不存在"
fi

echo ""
echo "🧪 8. 连接测试"
echo "-----------------------------------"

# 测试不同路径
TEST_URLS=(
    "https://www.besthammer.club/"
    "https://www.besthammer.club/en/"
    "https://www.besthammer.club/cloudflare-test.php"
)

for url in "${TEST_URLS[@]}"; do
    response=$(curl -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || echo "000")
    if [ "$response" = "200" ]; then
        log_success "$url - HTTP $response"
    else
        log_error "$url - HTTP $response"
    fi
done

echo ""
echo "📋 9. 诊断总结"
echo "=================================="

echo ""
echo "🔧 针对Cloudflare环境的修复建议:"
echo ""

if [ "$HTTPS_RESPONSE" = "404" ]; then
    echo "❗ 主要问题：HTTPS返回404错误"
    echo ""
    echo "🛠️ 解决步骤："
    echo "1. 运行Cloudflare专用修复脚本："
    echo "   sudo bash fix-apache-cloudflare.sh"
    echo ""
    echo "2. 在FastPanel面板中确保："
    echo "   - 域名指向: $PUBLIC_DIR"
    echo "   - SSL设置: 启用"
    echo ""
    echo "3. 在Cloudflare面板中确保："
    echo "   - DNS记录: A记录指向服务器IP（橙色云朵=代理开启）"
    echo "   - SSL/TLS模式: 完全 或 完全(严格)"
    echo "   - 缓存: 可临时开启开发模式进行测试"
fi

echo ""
echo "☁️ Cloudflare设置检查清单："
echo "□ DNS记录正确（A记录指向服务器IP）"
echo "□ 代理状态开启（橙色云朵图标）"
echo "□ SSL/TLS模式设置为'完全'或'完全(严格)'"
echo "□ 页面规则未阻止访问"
echo "□ 防火墙规则未阻止访问"
echo ""
echo "🖥️ 服务器设置检查清单："
echo "□ Apache虚拟主机DocumentRoot指向public目录"
echo "□ Apache RemoteIP模块启用（获取真实IP）"
echo "□ Laravel应用密钥已生成"
echo "□ 文件权限正确设置"
echo ""

echo "📞 如需进一步帮助，请提供："
echo "1. 此诊断报告的完整输出"
echo "2. Cloudflare DNS设置截图"
echo "3. FastPanel域名配置截图"

#!/bin/bash

# 502错误精准修复脚本
# 专门解决FastPanel重启后的502网关错误

set -e

echo "🔧 502错误精准修复"
echo "=================="
echo "目标：修复Nginx与PHP-FPM连接问题"
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
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${PURPLE}[STEP]${NC} $1"
}

# 检查是否为root用户
if [ "$EUID" -ne 0 ]; then
    log_error "请使用 root 用户或 sudo 运行此脚本"
    exit 1
fi

PROJECT_DIR="/var/www/besthammer_c_usr/data/www/besthammer.club"
PUBLIC_DIR="$PROJECT_DIR/public"

log_step "第1步：诊断502错误原因"
echo "-----------------------------------"

# 检查Nginx状态
if systemctl is-active --quiet nginx; then
    log_success "Nginx服务运行正常"
else
    log_error "Nginx服务未运行"
    systemctl start nginx
fi

# 检查Nginx错误日志
log_info "检查Nginx错误日志..."
if [ -f "/var/log/nginx/error.log" ]; then
    echo "最近的Nginx错误："
    tail -n 5 /var/log/nginx/error.log | grep -E "(502|upstream|connect)" || echo "   未发现502相关错误"
fi

if [ -f "/var/log/nginx/besthammer.club_error.log" ]; then
    echo "站点错误日志："
    tail -n 5 /var/log/nginx/besthammer.club_error.log | grep -E "(502|upstream|connect)" || echo "   未发现502相关错误"
fi

log_step "第2步：检查和修复PHP-FPM服务"
echo "-----------------------------------"

# 检测所有PHP-FPM服务
PHP_VERSIONS=("8.3" "8.2" "8.1" "8.0")
WORKING_PHP=""
WORKING_SOCKET=""

for version in "${PHP_VERSIONS[@]}"; do
    service_name="php${version}-fpm"
    
    log_info "检查PHP ${version}-FPM..."
    
    if systemctl list-unit-files | grep -q "$service_name"; then
        # 重启服务
        systemctl restart "$service_name" 2>/dev/null || true
        sleep 2
        
        if systemctl is-active --quiet "$service_name"; then
            log_success "PHP ${version}-FPM 运行正常"
            
            # 检查socket文件
            SOCKET_PATHS=(
                "/var/run/php/php${version}-fpm.sock"
                "/run/php/php${version}-fpm.sock"
            )
            
            for socket in "${SOCKET_PATHS[@]}"; do
                if [ -S "$socket" ]; then
                    log_success "找到socket: $socket"
                    
                    # 检查socket权限
                    SOCKET_PERMS=$(stat -c '%a' "$socket")
                    SOCKET_OWNER=$(stat -c '%U:%G' "$socket")
                    log_info "Socket权限: $SOCKET_PERMS ($SOCKET_OWNER)"
                    
                    # 确保权限正确
                    chown www-data:www-data "$socket"
                    chmod 660 "$socket"
                    
                    WORKING_PHP="$version"
                    WORKING_SOCKET="$socket"
                    break
                fi
            done
            
            if [ -n "$WORKING_SOCKET" ]; then
                break
            fi
        else
            log_warning "PHP ${version}-FPM 启动失败"
            systemctl status "$service_name" --no-pager -l | head -3
        fi
    fi
done

if [ -z "$WORKING_PHP" ]; then
    log_error "未找到可用的PHP-FPM服务，尝试安装..."
    
    # 安装PHP 8.3-FPM
    apt update
    apt install -y php8.3-fpm php8.3-mysql php8.3-xml php8.3-mbstring php8.3-curl php8.3-zip php8.3-gd
    
    systemctl start php8.3-fpm
    systemctl enable php8.3-fpm
    
    WORKING_PHP="8.3"
    WORKING_SOCKET="/var/run/php/php8.3-fpm.sock"
    
    # 设置权限
    chown www-data:www-data "$WORKING_SOCKET"
    chmod 660 "$WORKING_SOCKET"
    
    log_success "PHP 8.3-FPM已安装并配置"
fi

log_info "使用PHP版本: $WORKING_PHP"
log_info "使用Socket: $WORKING_SOCKET"

log_step "第3步：修复Nginx配置"
echo "-----------------------------------"

# 创建修复后的Nginx配置
NGINX_CONFIG="/etc/nginx/sites-available/besthammer.club"

log_info "创建修复后的Nginx配置..."

cat > "$NGINX_CONFIG" << EOF
# 502错误修复版Nginx配置
server {
    listen 80;
    listen [::]:80;
    server_name besthammer.club www.besthammer.club;
    
    # Cloudflare真实IP
    real_ip_header CF-Connecting-IP;
    set_real_ip_from 0.0.0.0/0;
    
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name besthammer.club www.besthammer.club;
    
    # SSL配置
    ssl_certificate /etc/ssl/certs/ssl-cert-snakeoil.pem;
    ssl_certificate_key /etc/ssl/private/ssl-cert-snakeoil.key;
    
    # Cloudflare真实IP
    real_ip_header CF-Connecting-IP;
    set_real_ip_from 0.0.0.0/0;
    
    # 项目配置
    root $PUBLIC_DIR;
    index index.php index.html;
    
    # 详细错误日志
    access_log /var/log/nginx/besthammer.club_access.log;
    error_log /var/log/nginx/besthammer.club_error.log debug;
    
    # Laravel URL重写
    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }
    
    # PHP处理 - 502错误修复版
    location ~ \.php$ {
        # 确保文件存在
        try_files \$uri =404;
        
        # FastCGI配置
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        
        # 使用检测到的socket
        fastcgi_pass unix:$WORKING_SOCKET;
        fastcgi_index index.php;
        
        # 基础参数
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$realpath_root\$fastcgi_script_name;
        fastcgi_param DOCUMENT_ROOT \$realpath_root;
        
        # 环境变量
        fastcgi_param HTTPS on;
        fastcgi_param APP_ENV production;
        
        # Cloudflare头
        fastcgi_param HTTP_CF_CONNECTING_IP \$http_cf_connecting_ip;
        fastcgi_param HTTP_X_FORWARDED_PROTO \$http_x_forwarded_proto;
        
        # 超时设置（防止502）
        fastcgi_connect_timeout 300;
        fastcgi_send_timeout 300;
        fastcgi_read_timeout 300;
        
        # 缓冲设置（防止502）
        fastcgi_buffer_size 128k;
        fastcgi_buffers 8 128k;
        fastcgi_busy_buffers_size 256k;
        fastcgi_temp_file_write_size 256k;
    }
    
    # 静态文件
    location ~* \.(css|js|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
        try_files \$uri =404;
    }
    
    # 安全设置
    location ~ /\. {
        deny all;
    }
}
EOF

# 测试Nginx配置
if nginx -t; then
    log_success "Nginx配置测试通过"
else
    log_error "Nginx配置有错误"
    nginx -t
    exit 1
fi

log_step "第4步：测试PHP-FPM连接"
echo "-----------------------------------"

# 创建PHP-FPM连接测试脚本
cat > "/tmp/test_fpm.php" << 'EOF'
<?php
echo "PHP-FPM连接测试成功！\n";
echo "PHP版本: " . PHP_VERSION . "\n";
echo "SAPI: " . php_sapi_name() . "\n";
echo "时间: " . date('Y-m-d H:i:s') . "\n";
?>
EOF

# 使用cgi-fcgi测试连接（如果可用）
if command -v cgi-fcgi &> /dev/null; then
    log_info "测试PHP-FPM连接..."
    if SCRIPT_FILENAME="/tmp/test_fmp.php" cgi-fcgi -bind -connect "$WORKING_SOCKET" < /dev/null; then
        log_success "PHP-FPM连接测试成功"
    else
        log_warning "PHP-FPM连接测试失败"
    fi
else
    log_info "cgi-fcgi不可用，跳过连接测试"
fi

rm -f "/tmp/test_fpm.php"

log_step "第5步：重启服务并验证"
echo "-----------------------------------"

# 重启PHP-FPM
systemctl restart "php$WORKING_PHP-fpm"
sleep 2

if systemctl is-active --quiet "php$WORKING_PHP-fpm"; then
    log_success "PHP-FPM重启成功"
else
    log_error "PHP-FPM重启失败"
    systemctl status "php$WORKING_PHP-fpm"
    exit 1
fi

# 重启Nginx
systemctl restart nginx
sleep 2

if systemctl is-active --quiet nginx; then
    log_success "Nginx重启成功"
else
    log_error "Nginx重启失败"
    systemctl status nginx
    exit 1
fi

log_step "第6步：创建502测试页面"
echo "-----------------------------------"

cat > "$PUBLIC_DIR/502-test.php" << 'EOF'
<?php
header('Content-Type: text/html; charset=utf-8');

$status = [
    'nginx' => $_SERVER['SERVER_SOFTWARE'] ?? 'Unknown',
    'php_version' => PHP_VERSION,
    'php_sapi' => php_sapi_name(),
    'timestamp' => date('Y-m-d H:i:s T'),
    'memory_usage' => memory_get_usage(true),
    'cf_ray' => $_SERVER['HTTP_CF_RAY'] ?? 'N/A'
];
?>
<!DOCTYPE html>
<html>
<head>
    <title>502错误修复验证</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background: #f8f9fa; }
        .container { max-width: 800px; margin: 0 auto; background: white; padding: 30px; border-radius: 10px; box-shadow: 0 4px 6px rgba(0,0,0,0.1); }
        .success { color: #28a745; font-weight: bold; font-size: 20px; }
        .info { color: #007bff; }
        table { width: 100%; border-collapse: collapse; margin: 20px 0; }
        th, td { padding: 12px; text-align: left; border-bottom: 1px solid #ddd; }
        th { background-color: #f8f9fa; }
        .status-ok { background-color: #d4edda; }
    </style>
</head>
<body>
    <div class="container">
        <h1 class="success">✅ 502错误已修复！</h1>
        
        <p>如果您能看到这个页面，说明Nginx与PHP-FPM连接正常，502错误已解决。</p>
        
        <h2>系统状态</h2>
        <table>
            <tr><th>项目</th><th>值</th></tr>
            <tr class="status-ok"><td>Web服务器</td><td><?php echo $status['nginx']; ?></td></tr>
            <tr class="status-ok"><td>PHP版本</td><td><?php echo $status['php_version']; ?></td></tr>
            <tr class="status-ok"><td>PHP SAPI</td><td><?php echo $status['php_sapi']; ?></td></tr>
            <tr><td>测试时间</td><td><?php echo $status['timestamp']; ?></td></tr>
            <tr><td>内存使用</td><td><?php echo round($status['memory_usage']/1024/1024, 2); ?> MB</td></tr>
            <tr><td>CF-Ray</td><td><?php echo $status['cf_ray']; ?></td></tr>
        </table>
        
        <h2>功能测试</h2>
        <p>
            <a href="/" style="display: inline-block; margin: 5px; padding: 10px 20px; background: #007bff; color: white; text-decoration: none; border-radius: 5px;">🏠 Laravel首页</a>
            <a href="/en/" style="display: inline-block; margin: 5px; padding: 10px 20px; background: #28a745; color: white; text-decoration: none; border-radius: 5px;">🇺🇸 英语版本</a>
        </p>
        
        <div style="background: #d4edda; padding: 15px; border-radius: 5px; border-left: 4px solid #28a745; margin: 20px 0;">
            <strong>502错误修复成功！</strong><br>
            Nginx与PHP-FPM连接正常，网站应该可以正常访问了。
        </div>
    </div>
</body>
</html>
EOF

# 设置文件权限
chown -R www-data:www-data "$PROJECT_DIR"
chmod -R 755 "$PROJECT_DIR"
chmod -R 775 "$PROJECT_DIR/storage"
chmod -R 775 "$PROJECT_DIR/bootstrap/cache"

log_success "502测试页面创建完成"

echo ""
echo "🎉 502错误修复完成！"
echo "===================="
echo ""
echo "📋 修复摘要："
echo "✅ PHP $WORKING_PHP-FPM 服务已重启"
echo "✅ Socket文件权限已修复: $WORKING_SOCKET"
echo "✅ Nginx配置已优化"
echo "✅ 超时和缓冲设置已调整"
echo "✅ 服务已重启"
echo ""
echo "🧪 立即测试："
echo "   https://www.besthammer.club/502-test.php"
echo ""
echo "🎯 如果测试页面正常显示，说明502错误已解决！"
echo "   然后可以测试："
echo "   - Laravel首页: https://www.besthammer.club/"
echo "   - 多语言路由: https://www.besthammer.club/en/"
echo ""
echo "🔍 如果仍有502错误，请检查："
echo "   tail -f /var/log/nginx/besthammer.club_error.log"
echo ""
log_info "502错误修复完成！请测试网站访问！"

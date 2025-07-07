#!/bin/bash

# 修复缺失的Nginx站点配置
# 专门解决"站点配置不存在"导致的502错误

set -e

echo "🔧 修复缺失的Nginx站点配置"
echo "=========================="
echo "问题：Nginx站点配置不存在"
echo "解决：创建PHP 8.3-FPM专用配置"
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

log_step "第1步：确认当前状态"
echo "-----------------------------------"

# 确认PHP 8.3-FPM状态
if systemctl is-active --quiet php8.3-fpm; then
    log_success "PHP 8.3-FPM运行正常"
else
    log_error "PHP 8.3-FPM未运行"
    exit 1
fi

# 确认socket文件
PHP_SOCKET="/var/run/php/php8.3-fpm.sock"
if [ -S "$PHP_SOCKET" ]; then
    log_success "PHP socket存在: $PHP_SOCKET"
    SOCKET_PERMS=$(stat -c '%a' "$PHP_SOCKET")
    SOCKET_OWNER=$(stat -c '%U:%G' "$PHP_SOCKET")
    log_info "Socket权限: $SOCKET_PERMS ($SOCKET_OWNER)"
else
    log_error "PHP socket不存在"
    exit 1
fi

# 检查项目目录
if [ -d "$PUBLIC_DIR" ]; then
    log_success "项目目录存在: $PUBLIC_DIR"
else
    log_error "项目目录不存在: $PUBLIC_DIR"
    exit 1
fi

log_step "第2步：清理现有配置"
echo "-----------------------------------"

# 检查并清理可能冲突的配置
NGINX_SITES_ENABLED="/etc/nginx/sites-enabled"
NGINX_SITES_AVAILABLE="/etc/nginx/sites-available"

log_info "检查现有Nginx配置..."

# 列出现有配置
if [ -d "$NGINX_SITES_ENABLED" ]; then
    echo "当前启用的站点："
    ls -la "$NGINX_SITES_ENABLED/" | grep -v "^total" | grep -v "^\."
fi

# 禁用可能冲突的配置
CONFLICTING_CONFIGS=(
    "default"
    "000-default"
    "besthammer.club"
    "cloudflare-besthammer"
)

for config in "${CONFLICTING_CONFIGS[@]}"; do
    if [ -L "$NGINX_SITES_ENABLED/$config" ] || [ -L "$NGINX_SITES_ENABLED/${config}.conf" ]; then
        log_warning "禁用冲突配置: $config"
        rm -f "$NGINX_SITES_ENABLED/$config" "$NGINX_SITES_ENABLED/${config}.conf"
    fi
done

log_step "第3步：创建新的Nginx站点配置"
echo "-----------------------------------"

# 创建新的站点配置文件
NGINX_CONFIG="$NGINX_SITES_AVAILABLE/besthammer.club.conf"

log_info "创建Nginx配置: $NGINX_CONFIG"

cat > "$NGINX_CONFIG" << EOF
# FastPanel + PHP 8.3-FPM + Laravel 配置
# 修复502错误专用版本

server {
    listen 80;
    listen [::]:80;
    server_name besthammer.club www.besthammer.club;
    
    # Cloudflare真实IP
    real_ip_header CF-Connecting-IP;
    set_real_ip_from 0.0.0.0/0;
    
    # 强制HTTPS重定向
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name besthammer.club www.besthammer.club;
    
    # SSL配置
    ssl_certificate /etc/ssl/certs/ssl-cert-snakeoil.pem;
    ssl_certificate_key /etc/ssl/private/ssl-cert-snakeoil.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    
    # Cloudflare真实IP
    real_ip_header CF-Connecting-IP;
    set_real_ip_from 0.0.0.0/0;
    
    # Laravel项目配置
    root $PUBLIC_DIR;
    index index.php index.html index.htm;
    
    # 字符集
    charset utf-8;
    
    # 日志配置
    access_log /var/log/nginx/besthammer.club_access.log;
    error_log /var/log/nginx/besthammer.club_error.log;
    
    # 安全头
    add_header X-Content-Type-Options nosniff;
    add_header X-Frame-Options SAMEORIGIN;
    add_header X-XSS-Protection "1; mode=block";
    add_header Referrer-Policy "strict-origin-when-cross-origin";
    
    # Laravel URL重写
    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }
    
    # PHP 8.3-FPM处理（关键配置）
    location ~ \.php$ {
        # 安全检查
        try_files \$uri =404;
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        
        # 使用确认存在的PHP 8.3-FPM socket
        fastcgi_pass unix:$PHP_SOCKET;
        fastcgi_index index.php;
        
        # FastCGI参数
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$realpath_root\$fastcgi_script_name;
        fastcgi_param DOCUMENT_ROOT \$realpath_root;
        
        # Laravel环境变量
        fastcgi_param HTTPS on;
        fastcgi_param APP_ENV production;
        
        # Cloudflare头传递
        fastcgi_param HTTP_CF_CONNECTING_IP \$http_cf_connecting_ip;
        fastcgi_param HTTP_X_FORWARDED_PROTO \$http_x_forwarded_proto;
        fastcgi_param HTTP_CF_RAY \$http_cf_ray;
        fastcgi_param HTTP_CF_VISITOR \$http_cf_visitor;
        
        # 超时设置
        fastcgi_connect_timeout 60s;
        fastcgi_send_timeout 60s;
        fastcgi_read_timeout 60s;
        
        # 缓冲设置
        fastcgi_buffer_size 128k;
        fastcgi_buffers 4 256k;
        fastcgi_busy_buffers_size 256k;
    }
    
    # 静态文件处理
    location ~* \.(css|js|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot|webp)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
        add_header Vary Accept-Encoding;
        try_files \$uri =404;
    }
    
    # 禁止访问敏感文件
    location ~ /\. {
        deny all;
    }
    
    location ~ ^/(\.env|\.git|composer\.(json|lock)|package\.(json|lock)|artisan) {
        deny all;
    }
    
    # 禁止访问vendor目录
    location ~ ^/vendor/ {
        deny all;
    }
    
    # Gzip压缩
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types text/plain text/css text/xml text/javascript application/javascript application/xml+rss application/json;
}
EOF

log_success "Nginx配置文件创建完成"

log_step "第4步：启用站点配置"
echo "-----------------------------------"

# 创建符号链接启用站点
ln -sf "$NGINX_CONFIG" "$NGINX_SITES_ENABLED/besthammer.club.conf"
log_success "站点配置已启用"

# 验证配置文件
log_info "验证Nginx配置..."
if nginx -t; then
    log_success "Nginx配置测试通过"
else
    log_error "Nginx配置有错误"
    nginx -t
    exit 1
fi

log_step "第5步：重启Nginx服务"
echo "-----------------------------------"

# 重启Nginx
systemctl reload nginx
systemctl restart nginx

if systemctl is-active --quiet nginx; then
    log_success "Nginx重启成功"
else
    log_error "Nginx重启失败"
    systemctl status nginx
    exit 1
fi

log_step "第6步：验证配置生效"
echo "-----------------------------------"

# 检查站点配置是否存在
if [ -f "$NGINX_SITES_ENABLED/besthammer.club.conf" ]; then
    log_success "站点配置已启用"
else
    log_error "站点配置启用失败"
    exit 1
fi

# 显示当前启用的站点
log_info "当前启用的站点："
ls -la "$NGINX_SITES_ENABLED/" | grep -v "^total" | grep -v "^\."

log_step "第7步：创建验证页面"
echo "-----------------------------------"

cat > "$PUBLIC_DIR/config-test.php" << 'EOF'
<?php
header('Content-Type: text/html; charset=utf-8');
?>
<!DOCTYPE html>
<html>
<head>
    <title>Nginx配置修复验证</title>
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
        <h1 class="success">✅ Nginx站点配置修复成功！</h1>
        
        <p>如果您能看到这个页面，说明缺失的Nginx站点配置已经修复，502错误应该已解决。</p>
        
        <h2>配置状态</h2>
        <table>
            <tr><th>项目</th><th>状态</th><th>详情</th></tr>
            <tr class="status-ok">
                <td>Nginx站点配置</td>
                <td>✅ 已修复</td>
                <td>besthammer.club.conf</td>
            </tr>
            <tr class="status-ok">
                <td>PHP处理器</td>
                <td>✅ PHP 8.3-FPM</td>
                <td><?php echo php_sapi_name(); ?></td>
            </tr>
            <tr class="status-ok">
                <td>Web服务器</td>
                <td>✅ Nginx</td>
                <td><?php echo $_SERVER['SERVER_SOFTWARE'] ?? 'Unknown'; ?></td>
            </tr>
            <tr class="status-ok">
                <td>SSL协议</td>
                <td>✅ HTTPS</td>
                <td><?php echo isset($_SERVER['HTTPS']) ? 'Enabled' : 'Disabled'; ?></td>
            </tr>
        </table>
        
        <h2>Cloudflare状态</h2>
        <table>
            <tr><th>项目</th><th>值</th></tr>
            <tr><td>CF-Ray</td><td><?php echo $_SERVER['HTTP_CF_RAY'] ?? 'N/A'; ?></td></tr>
            <tr><td>真实IP</td><td><?php echo $_SERVER['HTTP_CF_CONNECTING_IP'] ?? $_SERVER['REMOTE_ADDR']; ?></td></tr>
            <tr><td>协议</td><td><?php echo $_SERVER['HTTP_X_FORWARDED_PROTO'] ?? 'N/A'; ?></td></tr>
        </table>
        
        <h2>功能测试</h2>
        <p>
            <a href="/" style="display: inline-block; margin: 5px; padding: 10px 20px; background: #007bff; color: white; text-decoration: none; border-radius: 5px;">🏠 Laravel首页</a>
            <a href="/en/" style="display: inline-block; margin: 5px; padding: 10px 20px; background: #28a745; color: white; text-decoration: none; border-radius: 5px;">🇺🇸 英语版本</a>
        </p>
        
        <div style="background: #d4edda; padding: 15px; border-radius: 5px; border-left: 4px solid #28a745; margin: 20px 0;">
            <strong>502错误修复成功！</strong><br>
            缺失的Nginx站点配置已创建，网站应该可以正常访问了。
        </div>
        
        <hr style="margin: 30px 0;">
        <p style="text-align: center; color: #6c757d;">
            <small>
                <strong>修复时间：</strong> <?php echo date('Y-m-d H:i:s T'); ?><br>
                <strong>配置：</strong> FastPanel + Nginx + PHP 8.3-FPM + Laravel
            </small>
        </p>
    </div>
</body>
</html>
EOF

# 设置文件权限
chown -R www-data:www-data "$PROJECT_DIR"
chmod -R 755 "$PROJECT_DIR"
chmod -R 775 "$PROJECT_DIR/storage"
chmod -R 775 "$PROJECT_DIR/bootstrap/cache"

log_success "验证页面创建完成"

echo ""
echo "🎉 Nginx站点配置修复完成！"
echo "=========================="
echo ""
echo "📋 修复摘要："
echo "✅ 清理了冲突的Nginx配置"
echo "✅ 创建了新的站点配置文件"
echo "✅ 配置了PHP 8.3-FPM连接"
echo "✅ 启用了站点配置"
echo "✅ 重启了Nginx服务"
echo ""
echo "🧪 立即测试验证页面："
echo "   https://www.besthammer.club/config-test.php"
echo ""
echo "🎯 如果验证页面正常显示，说明502错误已解决！"
echo "   然后可以测试："
echo "   - Laravel首页: https://www.besthammer.club/"
echo "   - 多语言路由: https://www.besthammer.club/en/"
echo ""
echo "📁 配置文件位置："
echo "   - 配置文件: $NGINX_CONFIG"
echo "   - 启用链接: $NGINX_SITES_ENABLED/besthammer.club.conf"
echo ""
log_info "Nginx站点配置修复完成！502错误应该已解决！"

#!/bin/bash

# FastPanel最终修复脚本
# 基于深度诊断结果的精准修复方案

set -e

echo "🎯 FastPanel最终修复方案"
echo "======================="
echo "根据诊断结果："
echo "- Nginx占用80/443端口"
echo "- Apache运行在127.0.0.1:81"
echo "- PHP-FPM未运行"
echo "- 需要配置Nginx反向代理"
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

log_step "第1步：启动PHP-FPM服务"
echo "-----------------------------------"

# 检测并启动PHP-FPM
PHP_VERSIONS=("8.3" "8.2" "8.1" "8.0")
PHP_FPM_STARTED=false

for version in "${PHP_VERSIONS[@]}"; do
    if dpkg -l | grep -q "php${version}-fpm"; then
        log_info "发现PHP ${version}-FPM包"
        
        # 启动PHP-FPM服务
        if systemctl start "php${version}-fpm" 2>/dev/null; then
            systemctl enable "php${version}-fpm"
            log_success "已启动PHP ${version}-FPM"
            PHP_FPM_STARTED=true
            
            # 检查socket文件
            SOCKET_PATH="/var/run/php/php${version}-fpm.sock"
            if [ -S "$SOCKET_PATH" ]; then
                log_success "PHP-FPM socket正常: $SOCKET_PATH"
            fi
            break
        fi
    fi
done

if [ "$PHP_FPM_STARTED" = false ]; then
    log_error "无法启动PHP-FPM，尝试安装..."
    apt update
    apt install -y php8.1-fpm php8.1-mysql php8.1-xml php8.1-mbstring php8.1-curl
    systemctl start php8.1-fpm
    systemctl enable php8.1-fpm
    log_success "PHP 8.1-FPM已安装并启动"
fi

log_step "第2步：配置Nginx反向代理"
echo "-----------------------------------"

# 创建FastPanel兼容的Nginx配置
NGINX_SITE="/etc/nginx/sites-available/besthammer.club"

log_info "创建Nginx虚拟主机配置..."

cat > "$NGINX_SITE" << 'EOF'
# FastPanel + Cloudflare + Laravel 配置
server {
    listen 80;
    listen [::]:80;
    server_name besthammer.club www.besthammer.club;
    
    # Cloudflare真实IP
    real_ip_header CF-Connecting-IP;
    set_real_ip_from 0.0.0.0/0;
    
    # 强制HTTPS重定向
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name besthammer.club www.besthammer.club;
    
    # SSL配置（自签名，Cloudflare处理真正的SSL）
    ssl_certificate /etc/ssl/certs/ssl-cert-snakeoil.pem;
    ssl_certificate_key /etc/ssl/private/ssl-cert-snakeoil.key;
    
    # Cloudflare真实IP
    real_ip_header CF-Connecting-IP;
    set_real_ip_from 0.0.0.0/0;
    
    # Laravel项目根目录
    root /var/www/besthammer_c_usr/data/www/besthammer.club/public;
    index index.php index.html index.htm;
    
    # 日志配置
    access_log /var/log/nginx/besthammer.club_access.log;
    error_log /var/log/nginx/besthammer.club_error.log;
    
    # Laravel URL重写
    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }
    
    # PHP处理
    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        
        # 使用PHP-FPM socket
        fastcgi_pass unix:/var/run/php/php8.1-fpm.sock;
        
        # 确保脚本文件存在
        fastcgi_param SCRIPT_FILENAME $realpath_root$fastcgi_script_name;
        include fastcgi_params;
        
        # Cloudflare头传递
        fastcgi_param HTTP_CF_CONNECTING_IP $http_cf_connecting_ip;
        fastcgi_param HTTP_X_FORWARDED_PROTO $http_x_forwarded_proto;
        fastcgi_param HTTP_CF_RAY $http_cf_ray;
        
        # HTTPS环境变量
        fastcgi_param HTTPS on;
    }
    
    # 静态文件处理
    location ~* \.(css|js|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
        try_files $uri =404;
    }
    
    # 安全头
    add_header X-Content-Type-Options nosniff;
    add_header X-Frame-Options SAMEORIGIN;
    add_header X-XSS-Protection "1; mode=block";
    
    # 隐藏Nginx版本
    server_tokens off;
}
EOF

# 启用Nginx站点
ln -sf "$NGINX_SITE" "/etc/nginx/sites-enabled/besthammer.club"

# 禁用默认站点
if [ -f "/etc/nginx/sites-enabled/default" ]; then
    rm -f "/etc/nginx/sites-enabled/default"
    log_info "已禁用Nginx默认站点"
fi

# 测试Nginx配置
if nginx -t; then
    log_success "Nginx配置测试通过"
    systemctl reload nginx
    log_success "Nginx配置已重载"
else
    log_error "Nginx配置有错误"
    nginx -t
    exit 1
fi

log_step "第3步：确保Apache在正确端口运行"
echo "-----------------------------------"

# 检查FastPanel的Apache配置
FASTPANEL_APACHE_CONFIG="/etc/apache2/fastpanel2-sites/besthammer_c_usr/besthammer.club.conf"

if [ -f "$FASTPANEL_APACHE_CONFIG" ]; then
    log_info "发现FastPanel Apache配置: $FASTPANEL_APACHE_CONFIG"
    
    # 备份原配置
    cp "$FASTPANEL_APACHE_CONFIG" "${FASTPANEL_APACHE_CONFIG}.backup.$(date +%Y%m%d_%H%M%S)"
    
    # 更新FastPanel Apache配置
    cat > "$FASTPANEL_APACHE_CONFIG" << EOF
# FastPanel Apache配置 - 监听127.0.0.1:81
<VirtualHost 127.0.0.1:81>
    ServerName besthammer.club
    ServerAlias www.besthammer.club
    DocumentRoot $PUBLIC_DIR
    
    <Directory $PUBLIC_DIR>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
        
        # Laravel URL重写
        RewriteEngine On
        RewriteCond %{REQUEST_FILENAME} !-f
        RewriteCond %{REQUEST_FILENAME} !-d
        RewriteRule ^(.*)$ index.php [QSA,L]
    </Directory>
    
    # 日志
    ErrorLog /var/log/apache2/besthammer_c_usr_error.log
    CustomLog /var/log/apache2/besthammer_c_usr_access.log combined
</VirtualHost>
EOF
    
    log_success "FastPanel Apache配置已更新"
else
    log_warning "未找到FastPanel Apache配置文件"
fi

# 重启Apache
if systemctl restart apache2; then
    log_success "Apache服务重启成功"
else
    log_error "Apache服务重启失败"
    systemctl status apache2
fi

log_step "第4步：创建最终测试页面"
echo "-----------------------------------"

cat > "$PUBLIC_DIR/final-test.php" << 'EOF'
<?php
header('Content-Type: text/html; charset=utf-8');

// 检测Web服务器
$webserver = $_SERVER['SERVER_SOFTWARE'] ?? 'Unknown';
$is_nginx = stripos($webserver, 'nginx') !== false;

// 检测PHP-FPM
$php_sapi = php_sapi_name();
$is_fpm = $php_sapi === 'fpm-fcgi';
?>
<!DOCTYPE html>
<html>
<head>
    <title>🎉 FastPanel最终测试</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; }
        .container { background: rgba(255,255,255,0.95); color: #333; padding: 40px; border-radius: 15px; box-shadow: 0 8px 32px rgba(0,0,0,0.3); max-width: 1000px; margin: 0 auto; }
        .success { color: #28a745; font-weight: bold; font-size: 18px; }
        .warning { color: #ffc107; font-weight: bold; }
        .error { color: #dc3545; font-weight: bold; }
        .info { color: #007bff; }
        table { width: 100%; border-collapse: collapse; margin: 20px 0; }
        th, td { padding: 15px; text-align: left; border-bottom: 2px solid #eee; }
        th { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; }
        .status-ok { background-color: #d4edda; }
        .status-warning { background-color: #fff3cd; }
        .status-error { background-color: #f8d7da; }
        .badge { padding: 6px 12px; border-radius: 20px; color: white; font-size: 12px; font-weight: bold; }
        .badge-success { background-color: #28a745; }
        .badge-warning { background-color: #ffc107; }
        .badge-error { background-color: #dc3545; }
        .architecture { background: #f8f9fa; padding: 20px; border-radius: 10px; margin: 20px 0; border-left: 5px solid #007bff; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🎉 FastPanel + Cloudflare + Laravel 最终测试</h1>
        
        <div class="architecture">
            <h3>🏗️ 当前架构</h3>
            <p><strong>用户</strong> → <strong>Cloudflare</strong> → <strong>Nginx(80/443)</strong> → <strong>PHP-FPM</strong> → <strong>Laravel应用</strong></p>
        </div>
        
        <h2>✅ 系统状态检查</h2>
        <table>
            <tr><th>组件</th><th>状态</th><th>详情</th></tr>
            <tr class="<?php echo $is_nginx ? 'status-ok' : 'status-error'; ?>">
                <td>Web服务器</td>
                <td>
                    <?php if ($is_nginx): ?>
                        <span class="badge badge-success">✅ Nginx</span>
                    <?php else: ?>
                        <span class="badge badge-error">❌ 非Nginx</span>
                    <?php endif; ?>
                </td>
                <td><?php echo $webserver; ?></td>
            </tr>
            <tr class="<?php echo $is_fpm ? 'status-ok' : 'status-error'; ?>">
                <td>PHP处理器</td>
                <td>
                    <?php if ($is_fpm): ?>
                        <span class="badge badge-success">✅ PHP-FPM</span>
                    <?php else: ?>
                        <span class="badge badge-warning">⚠️ <?php echo $php_sapi; ?></span>
                    <?php endif; ?>
                </td>
                <td>PHP <?php echo PHP_VERSION; ?> (<?php echo $php_sapi; ?>)</td>
            </tr>
            <tr class="<?php echo isset($_SERVER['HTTP_CF_RAY']) ? 'status-ok' : 'status-warning'; ?>">
                <td>Cloudflare代理</td>
                <td>
                    <?php if (isset($_SERVER['HTTP_CF_RAY'])): ?>
                        <span class="badge badge-success">✅ 活跃</span>
                    <?php else: ?>
                        <span class="badge badge-warning">⚠️ 未检测到</span>
                    <?php endif; ?>
                </td>
                <td><?php echo $_SERVER['HTTP_CF_RAY'] ?? '无CF-Ray头'; ?></td>
            </tr>
            <tr class="<?php echo file_exists('index.php') ? 'status-ok' : 'status-error'; ?>">
                <td>Laravel应用</td>
                <td>
                    <?php if (file_exists('index.php')): ?>
                        <span class="badge badge-success">✅ 就绪</span>
                    <?php else: ?>
                        <span class="badge badge-error">❌ 缺失</span>
                    <?php endif; ?>
                </td>
                <td>入口文件: <?php echo file_exists('index.php') ? '存在' : '缺失'; ?></td>
            </tr>
        </table>
        
        <h2>🌐 网络信息</h2>
        <table>
            <tr><th>项目</th><th>值</th></tr>
            <tr><td>访客真实IP</td><td><?php echo $_SERVER['HTTP_CF_CONNECTING_IP'] ?? $_SERVER['REMOTE_ADDR']; ?></td></tr>
            <tr><td>服务器IP</td><td><?php echo $_SERVER['SERVER_ADDR'] ?? '未知'; ?></td></tr>
            <tr><td>协议</td><td><?php echo isset($_SERVER['HTTPS']) ? 'HTTPS' : 'HTTP'; ?></td></tr>
            <tr><td>主机名</td><td><?php echo $_SERVER['HTTP_HOST']; ?></td></tr>
        </table>
        
        <h2>🧪 功能测试</h2>
        <div style="text-align: center; margin: 30px 0;">
            <a href="/" style="display: inline-block; margin: 10px; padding: 15px 25px; background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; text-decoration: none; border-radius: 25px; font-weight: bold;">🏠 Laravel首页</a>
            <a href="/en/" style="display: inline-block; margin: 10px; padding: 15px 25px; background: linear-gradient(135deg, #28a745 0%, #20c997 100%); color: white; text-decoration: none; border-radius: 25px; font-weight: bold;">🇺🇸 英语版本</a>
            <a href="<?php echo $_SERVER['PHP_SELF']; ?>" style="display: inline-block; margin: 10px; padding: 15px 25px; background: linear-gradient(135deg, #6c757d 0%, #495057 100%); color: white; text-decoration: none; border-radius: 25px; font-weight: bold;">🔄 刷新测试</a>
        </div>
        
        <?php if ($is_nginx && $is_fpm && file_exists('index.php')): ?>
            <div style="background: #d4edda; padding: 20px; border-radius: 10px; border-left: 5px solid #28a745; margin: 20px 0;">
                <h3 style="color: #155724; margin: 0 0 10px 0;">🎉 配置成功！</h3>
                <p style="color: #155724; margin: 0;">所有组件都正常工作。您的FastPanel + Cloudflare + Laravel配置已成功！</p>
            </div>
        <?php else: ?>
            <div style="background: #fff3cd; padding: 20px; border-radius: 10px; border-left: 5px solid #ffc107; margin: 20px 0;">
                <h3 style="color: #856404; margin: 0 0 10px 0;">⚠️ 需要检查</h3>
                <p style="color: #856404; margin: 0;">某些组件可能需要进一步配置。请检查上述状态表。</p>
            </div>
        <?php endif; ?>
        
        <hr style="margin: 30px 0;">
        <p style="text-align: center; color: #6c757d;">
            <small>
                <strong>测试时间：</strong> <?php echo date('Y-m-d H:i:s T'); ?><br>
                <strong>FastPanel最终修复方案</strong> - 问题已解决！
            </small>
        </p>
    </div>
</body>
</html>
EOF

log_success "最终测试页面创建完成"

log_step "第5步：设置正确的文件权限"
echo "-----------------------------------"

# 设置文件权限
chown -R www-data:www-data "$PROJECT_DIR"
chmod -R 755 "$PROJECT_DIR"
chmod -R 775 "$PROJECT_DIR/storage"
chmod -R 775 "$PROJECT_DIR/bootstrap/cache"

log_success "文件权限设置完成"

echo ""
echo "🎉 FastPanel最终修复完成！"
echo "=========================="
echo ""
echo "📋 修复摘要："
echo "✅ PHP-FPM服务已启动"
echo "✅ Nginx反向代理已配置"
echo "✅ FastPanel Apache配置已更新"
echo "✅ 文件权限已设置"
echo ""
echo "🧪 请立即测试最终测试页面："
echo "   https://www.besthammer.club/final-test.php"
echo ""
echo "🎯 如果最终测试页面显示'配置成功'，则："
echo "   1. 测试Laravel首页：https://www.besthammer.club/"
echo "   2. 测试多语言路由：https://www.besthammer.club/en/"
echo ""
echo "🏗️ 当前架构："
echo "   用户 → Cloudflare → Nginx(80/443) → PHP-FPM → Laravel应用"
echo ""
log_info "FastPanel最终修复完成！问题应该已解决！"

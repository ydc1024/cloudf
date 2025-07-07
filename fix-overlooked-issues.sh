#!/bin/bash

# 修复被忽略的FastPanel + Cloudflare问题
# 针对深度分析发现的潜在问题

set -e

echo "🔧 修复被忽略的FastPanel + Cloudflare问题"
echo "========================================"
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

log_step "第1步：处理Nginx反向代理问题"
echo "-----------------------------------"

# 检查Nginx是否在运行
if systemctl is-active --quiet nginx; then
    log_warning "发现Nginx正在运行，这可能是404的根本原因！"
    
    # 创建Nginx虚拟主机配置
    NGINX_CONFIG="/etc/nginx/sites-available/besthammer.club"
    
    log_info "创建Nginx虚拟主机配置..."
    cat > "$NGINX_CONFIG" << EOF
# Nginx + Apache + Cloudflare 配置
server {
    listen 80;
    listen [::]:80;
    server_name besthammer.club www.besthammer.club;
    
    # 获取真实IP
    real_ip_header CF-Connecting-IP;
    set_real_ip_from 0.0.0.0/0;
    
    # 强制HTTPS重定向
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name besthammer.club www.besthammer.club;
    
    # SSL配置（自签名，因为Cloudflare处理真正的SSL）
    ssl_certificate /etc/ssl/certs/ssl-cert-snakeoil.pem;
    ssl_certificate_key /etc/ssl/private/ssl-cert-snakeoil.key;
    
    # 获取真实IP
    real_ip_header CF-Connecting-IP;
    set_real_ip_from 0.0.0.0/0;
    
    # 直接服务Laravel文件，不通过Apache
    root $PUBLIC_DIR;
    index index.php index.html index.htm;
    
    # Laravel URL重写
    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }
    
    # PHP处理
    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php8.1-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$realpath_root\$fastcgi_script_name;
        include fastcgi_params;
        
        # Cloudflare头传递
        fastcgi_param HTTP_CF_CONNECTING_IP \$http_cf_connecting_ip;
        fastcgi_param HTTP_X_FORWARDED_PROTO \$http_x_forwarded_proto;
    }
    
    # 静态文件缓存
    location ~* \.(css|js|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
    
    # 安全头
    add_header X-Content-Type-Options nosniff;
    add_header X-Frame-Options SAMEORIGIN;
    add_header X-XSS-Protection "1; mode=block";
}
EOF
    
    # 启用Nginx站点
    ln -sf "$NGINX_CONFIG" "/etc/nginx/sites-enabled/besthammer.club"
    
    # 禁用默认站点
    if [ -f "/etc/nginx/sites-enabled/default" ]; then
        rm -f "/etc/nginx/sites-enabled/default"
        log_info "已禁用Nginx默认站点"
    fi
    
    # 测试Nginx配置
    if nginx -t; then
        log_success "Nginx配置测试通过"
        systemctl reload nginx
    else
        log_error "Nginx配置有错误"
        nginx -t
    fi
    
else
    log_info "Nginx未运行，跳过Nginx配置"
fi

log_step "第2步：确保PHP-FPM运行"
echo "-----------------------------------"

# 检查并启动PHP-FPM
PHP_VERSIONS=("8.3" "8.2" "8.1" "8.0")
PHP_FPM_STARTED=false

for version in "${PHP_VERSIONS[@]}"; do
    if systemctl list-unit-files | grep -q "php${version}-fpm"; then
        log_info "发现PHP ${version}-FPM"
        if ! systemctl is-active --quiet "php${version}-fpm"; then
            systemctl start "php${version}-fpm"
            systemctl enable "php${version}-fpm"
            log_success "已启动PHP ${version}-FPM"
        else
            log_success "PHP ${version}-FPM已运行"
        fi
        PHP_FPM_STARTED=true
        break
    fi
done

if [ "$PHP_FPM_STARTED" = false ]; then
    log_warning "未发现PHP-FPM服务"
fi

log_step "第3步：修复Apache配置（备选方案）"
echo "-----------------------------------"

# 如果Nginx未运行，确保Apache配置正确
if ! systemctl is-active --quiet nginx; then
    log_info "配置Apache作为主要Web服务器..."
    
    # 创建简化的Apache配置
    APACHE_CONFIG="/etc/apache2/sites-available/000-default.conf"
    
    cat > "$APACHE_CONFIG" << EOF
# 简化的Apache默认配置
<VirtualHost *:80>
    DocumentRoot $PUBLIC_DIR
    
    <Directory $PUBLIC_DIR>
        AllowOverride All
        Require all granted
        Options -Indexes +FollowSymLinks
        
        RewriteEngine On
        RewriteCond %{REQUEST_FILENAME} !-f
        RewriteCond %{REQUEST_FILENAME} !-d
        RewriteRule ^(.*)$ index.php [QSA,L]
    </Directory>
    
    ErrorLog \${APACHE_LOG_DIR}/error.log
    CustomLog \${APACHE_LOG_DIR}/access.log combined
</VirtualHost>

<VirtualHost *:443>
    DocumentRoot $PUBLIC_DIR
    
    SSLEngine on
    SSLCertificateFile /etc/ssl/certs/ssl-cert-snakeoil.pem
    SSLCertificateKeyFile /etc/ssl/private/ssl-cert-snakeoil.key
    
    <Directory $PUBLIC_DIR>
        AllowOverride All
        Require all granted
        Options -Indexes +FollowSymLinks
        
        RewriteEngine On
        RewriteCond %{REQUEST_FILENAME} !-f
        RewriteCond %{REQUEST_FILENAME} !-d
        RewriteRule ^(.*)$ index.php [QSA,L]
    </Directory>
    
    ErrorLog \${APACHE_LOG_DIR}/ssl_error.log
    CustomLog \${APACHE_LOG_DIR}/ssl_access.log combined
</VirtualHost>
EOF
    
    # 启用站点和模块
    a2ensite 000-default.conf
    a2enmod rewrite ssl
    
    if apache2ctl configtest; then
        systemctl reload apache2
        log_success "Apache配置已更新"
    else
        log_error "Apache配置有错误"
    fi
fi

log_step "第4步：创建全面的测试页面"
echo "-----------------------------------"

# 创建多层次测试页面
cat > "$PUBLIC_DIR/comprehensive-test.php" << 'EOF'
<?php
header('Content-Type: text/html; charset=utf-8');

// 检测Web服务器类型
$webserver = $_SERVER['SERVER_SOFTWARE'] ?? 'Unknown';
$is_nginx = stripos($webserver, 'nginx') !== false;
$is_apache = stripos($webserver, 'apache') !== false;
?>
<!DOCTYPE html>
<html>
<head>
    <title>全面测试 - FastPanel + Cloudflare</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background: #f8f9fa; }
        .container { background: white; padding: 30px; border-radius: 10px; box-shadow: 0 4px 6px rgba(0,0,0,0.1); max-width: 1200px; margin: 0 auto; }
        .success { color: #28a745; font-weight: bold; }
        .warning { color: #ffc107; font-weight: bold; }
        .error { color: #dc3545; font-weight: bold; }
        .info { color: #007bff; }
        table { width: 100%; border-collapse: collapse; margin: 15px 0; }
        th, td { padding: 12px; text-align: left; border-bottom: 1px solid #ddd; }
        th { background-color: #f8f9fa; font-weight: bold; }
        .status-ok { background-color: #d4edda; }
        .status-warning { background-color: #fff3cd; }
        .status-error { background-color: #f8d7da; }
        .section { margin: 30px 0; }
        .badge { padding: 4px 8px; border-radius: 4px; color: white; font-size: 12px; }
        .badge-nginx { background-color: #269900; }
        .badge-apache { background-color: #d73502; }
        .badge-cloudflare { background-color: #f38020; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🔍 全面测试 - FastPanel + Cloudflare</h1>
        
        <div class="section">
            <h2>🌐 Web服务器检测</h2>
            <table>
                <tr><th>项目</th><th>值</th><th>状态</th></tr>
                <tr class="<?php echo $is_nginx ? 'status-ok' : ($is_apache ? 'status-warning' : 'status-error'); ?>">
                    <td>Web服务器</td>
                    <td>
                        <?php echo $webserver; ?>
                        <?php if ($is_nginx): ?>
                            <span class="badge badge-nginx">NGINX</span>
                        <?php elseif ($is_apache): ?>
                            <span class="badge badge-apache">APACHE</span>
                        <?php endif; ?>
                    </td>
                    <td>
                        <?php if ($is_nginx): ?>
                            <span class="success">✅ Nginx配置生效</span>
                        <?php elseif ($is_apache): ?>
                            <span class="warning">⚠️ Apache配置</span>
                        <?php else: ?>
                            <span class="error">❌ 未知服务器</span>
                        <?php endif; ?>
                    </td>
                </tr>
            </table>
        </div>
        
        <div class="section">
            <h2>☁️ Cloudflare代理检测</h2>
            <table>
                <tr><th>Cloudflare头</th><th>值</th><th>状态</th></tr>
                <tr>
                    <td>CF-Ray</td>
                    <td><?php echo $_SERVER['HTTP_CF_RAY'] ?? 'N/A'; ?></td>
                    <td class="<?php echo isset($_SERVER['HTTP_CF_RAY']) ? 'success' : 'error'; ?>">
                        <?php echo isset($_SERVER['HTTP_CF_RAY']) ? '✅ 检测到' : '❌ 未检测到'; ?>
                    </td>
                </tr>
                <tr>
                    <td>CF-Connecting-IP</td>
                    <td><?php echo $_SERVER['HTTP_CF_CONNECTING_IP'] ?? 'N/A'; ?></td>
                    <td class="<?php echo isset($_SERVER['HTTP_CF_CONNECTING_IP']) ? 'success' : 'warning'; ?>">
                        <?php echo isset($_SERVER['HTTP_CF_CONNECTING_IP']) ? '✅ 真实IP获取' : '⚠️ 未获取'; ?>
                    </td>
                </tr>
                <tr>
                    <td>X-Forwarded-Proto</td>
                    <td><?php echo $_SERVER['HTTP_X_FORWARDED_PROTO'] ?? 'N/A'; ?></td>
                    <td class="info">协议转发</td>
                </tr>
            </table>
        </div>
        
        <div class="section">
            <h2>📁 文件系统检测</h2>
            <table>
                <tr><th>项目</th><th>状态</th><th>详情</th></tr>
                <tr>
                    <td>当前目录</td>
                    <td class="info">📍</td>
                    <td><?php echo getcwd(); ?></td>
                </tr>
                <tr>
                    <td>文档根目录</td>
                    <td class="<?php echo strpos($_SERVER['DOCUMENT_ROOT'], '/public') !== false ? 'success' : 'warning'; ?>">
                        <?php echo strpos($_SERVER['DOCUMENT_ROOT'], '/public') !== false ? '✅' : '⚠️'; ?>
                    </td>
                    <td><?php echo $_SERVER['DOCUMENT_ROOT']; ?></td>
                </tr>
                <tr>
                    <td>Laravel入口文件</td>
                    <td class="<?php echo file_exists('index.php') ? 'success' : 'error'; ?>">
                        <?php echo file_exists('index.php') ? '✅' : '❌'; ?>
                    </td>
                    <td><?php echo file_exists('index.php') ? '存在' : '缺失'; ?></td>
                </tr>
                <tr>
                    <td>.htaccess文件</td>
                    <td class="<?php echo file_exists('.htaccess') ? 'success' : 'warning'; ?>">
                        <?php echo file_exists('.htaccess') ? '✅' : '⚠️'; ?>
                    </td>
                    <td><?php echo file_exists('.htaccess') ? '存在' : '缺失'; ?></td>
                </tr>
            </table>
        </div>
        
        <div class="section">
            <h2>🔧 PHP环境检测</h2>
            <table>
                <tr><th>项目</th><th>值</th></tr>
                <tr><td>PHP版本</td><td><?php echo PHP_VERSION; ?></td></tr>
                <tr><td>PHP SAPI</td><td><?php echo php_sapi_name(); ?></td></tr>
                <tr><td>内存限制</td><td><?php echo ini_get('memory_limit'); ?></td></tr>
                <tr><td>执行时间限制</td><td><?php echo ini_get('max_execution_time'); ?>秒</td></tr>
            </table>
        </div>
        
        <div class="section">
            <h2>🧪 功能测试</h2>
            <div style="margin: 20px 0;">
                <a href="/" style="display: inline-block; margin: 5px; padding: 10px 15px; background: #007bff; color: white; text-decoration: none; border-radius: 5px;">🏠 Laravel首页</a>
                <a href="/en/" style="display: inline-block; margin: 5px; padding: 10px 15px; background: #28a745; color: white; text-decoration: none; border-radius: 5px;">🇺🇸 英语版本</a>
                <a href="<?php echo $_SERVER['PHP_SELF']; ?>" style="display: inline-block; margin: 5px; padding: 10px 15px; background: #6c757d; color: white; text-decoration: none; border-radius: 5px;">🔄 刷新测试</a>
            </div>
        </div>
        
        <div class="section">
            <h2>📊 诊断建议</h2>
            <?php if ($is_nginx): ?>
                <div class="success">
                    ✅ <strong>Nginx配置生效</strong><br>
                    您的网站正在通过Nginx提供服务，这通常是最佳配置。
                </div>
            <?php elseif ($is_apache): ?>
                <div class="warning">
                    ⚠️ <strong>Apache配置</strong><br>
                    网站通过Apache提供服务。如果遇到问题，可能需要检查Apache虚拟主机配置。
                </div>
            <?php else: ?>
                <div class="error">
                    ❌ <strong>未知Web服务器</strong><br>
                    无法识别Web服务器类型，请检查服务器配置。
                </div>
            <?php endif; ?>
            
            <?php if (!isset($_SERVER['HTTP_CF_RAY'])): ?>
                <div class="error">
                    ❌ <strong>Cloudflare代理未检测到</strong><br>
                    请检查Cloudflare DNS设置，确保代理状态为开启（橙色云朵）。
                </div>
            <?php endif; ?>
        </div>
        
        <hr style="margin: 30px 0;">
        <p><small>
            <strong>测试时间：</strong> <?php echo date('Y-m-d H:i:s T'); ?><br>
            <strong>服务器IP：</strong> <?php echo $_SERVER['SERVER_ADDR'] ?? '未知'; ?><br>
            <strong>客户端IP：</strong> <?php echo $_SERVER['REMOTE_ADDR']; ?>
        </small></p>
    </div>
</body>
</html>
EOF

log_success "全面测试页面创建完成"

log_step "第5步：设置正确的文件权限"
echo "-----------------------------------"

# 设置文件权限
chown -R www-data:www-data "$PROJECT_DIR"
chmod -R 755 "$PROJECT_DIR"
chmod -R 775 "$PROJECT_DIR/storage"
chmod -R 775 "$PROJECT_DIR/bootstrap/cache"

log_success "文件权限设置完成"

echo ""
echo "🎉 被忽略问题修复完成！"
echo "========================"
echo ""
echo "🧪 请立即测试全面测试页面："
echo "   https://www.besthammer.club/comprehensive-test.php"
echo ""
echo "📋 这个页面将显示："
echo "   ✅ 当前使用的Web服务器（Nginx/Apache）"
echo "   ✅ Cloudflare代理状态"
echo "   ✅ 文件系统配置"
echo "   ✅ PHP环境信息"
echo "   ✅ 具体的诊断建议"
echo ""
echo "🔍 如果测试页面正常显示，说明基础配置已修复！"
echo "   然后可以测试Laravel应用：https://www.besthammer.club/"
echo ""
log_info "修复完成，请测试全面测试页面！"

#!/bin/bash

# 精准修复FastPanel + Cloudflare 404错误
# 基于诊断结果的针对性解决方案

set -e

echo "🎯 开始精准修复FastPanel + Cloudflare 404错误..."

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
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查是否为root用户
if [ "$EUID" -ne 0 ]; then
    log_error "请使用 root 用户或 sudo 运行此脚本"
    exit 1
fi

PROJECT_DIR="/var/www/besthammer_c_usr/data/www/besthammer.club"
PUBLIC_DIR="$PROJECT_DIR/public"

echo "🔧 第1步：修复Laravel应用URL配置"
echo "-----------------------------------"

cd "$PROJECT_DIR"

# 备份.env文件
if [ -f ".env" ]; then
    cp .env .env.backup.$(date +%Y%m%d_%H%M%S)
    log_info ".env文件已备份"
fi

# 修复APP_URL配置
sed -i 's|APP_URL=.*|APP_URL=https://www.besthammer.club|g' .env

# 确保其他关键配置正确
sed -i 's|APP_ENV=.*|APP_ENV=production|g' .env
sed -i 's|APP_DEBUG=.*|APP_DEBUG=false|g' .env

log_success "Laravel应用URL配置已修复"

echo ""
echo "🔧 第2步：清除所有Laravel缓存"
echo "-----------------------------------"

# 清除所有缓存
php artisan config:clear
php artisan cache:clear
php artisan route:clear
php artisan view:clear

# 重新生成缓存
php artisan config:cache
php artisan route:cache

log_success "Laravel缓存已清除并重新生成"

echo ""
echo "🔧 第3步：检查和修复.htaccess文件"
echo "-----------------------------------"

# 确保public目录有正确的.htaccess文件
cat > "$PUBLIC_DIR/.htaccess" << 'EOF'
<IfModule mod_rewrite.c>
    <IfModule mod_negotiation.c>
        Options -MultiViews -Indexes
    </IfModule>

    RewriteEngine On

    # Handle Authorization Header
    RewriteCond %{HTTP:Authorization} .
    RewriteRule .* - [E=HTTP_AUTHORIZATION:%{HTTP:Authorization}]

    # Redirect Trailing Slashes If Not A Folder...
    RewriteCond %{REQUEST_FILENAME} !-d
    RewriteCond %{REQUEST_URI} (.+)/$
    RewriteRule ^ %1 [L,R=301]

    # Send Requests To Front Controller...
    RewriteCond %{REQUEST_FILENAME} !-d
    RewriteCond %{REQUEST_FILENAME} !-f
    RewriteRule ^ index.php [L]
</IfModule>
EOF

log_success ".htaccess文件已更新"

echo ""
echo "🔧 第4步：重新配置Apache虚拟主机"
echo "-----------------------------------"

VHOST_FILE="/etc/apache2/sites-available/besthammer.club.conf"

# 备份现有配置
cp "$VHOST_FILE" "${VHOST_FILE}.backup.$(date +%Y%m%d_%H%M%S)"

# 创建新的虚拟主机配置
cat > "$VHOST_FILE" << EOF
# 精准修复版虚拟主机配置
<VirtualHost *:80>
    ServerName besthammer.club
    ServerAlias www.besthammer.club
    DocumentRoot $PUBLIC_DIR
    
    # 强制HTTPS重定向
    RewriteEngine On
    RewriteCond %{HTTP:X-Forwarded-Proto} !https [OR]
    RewriteCond %{HTTP:X-Forwarded-Proto} ^$
    RewriteCond %{HTTPS} !=on
    RewriteRule ^(.*)$ https://%{HTTP_HOST}%{REQUEST_URI} [L,R=301]
    
    <Directory $PUBLIC_DIR>
        Options -Indexes +FollowSymLinks +MultiViews
        AllowOverride All
        Require all granted
        
        # 确保URL重写工作
        RewriteEngine On
        RewriteCond %{REQUEST_FILENAME} !-f
        RewriteCond %{REQUEST_FILENAME} !-d
        RewriteRule ^(.*)$ index.php [QSA,L]
    </Directory>
    
    # 日志配置
    ErrorLog \${APACHE_LOG_DIR}/besthammer.club_error.log
    CustomLog \${APACHE_LOG_DIR}/besthammer.club_access.log combined
</VirtualHost>

<VirtualHost *:443>
    ServerName besthammer.club
    ServerAlias www.besthammer.club
    DocumentRoot $PUBLIC_DIR
    
    <Directory $PUBLIC_DIR>
        Options -Indexes +FollowSymLinks +MultiViews
        AllowOverride All
        Require all granted
        
        # Laravel URL重写规则
        RewriteEngine On
        RewriteCond %{REQUEST_FILENAME} !-f
        RewriteCond %{REQUEST_FILENAME} !-d
        RewriteRule ^(.*)$ index.php [QSA,L]
    </Directory>
    
    # SSL配置（Cloudflare环境）
    SSLEngine on
    SSLCertificateFile /etc/ssl/certs/ssl-cert-snakeoil.pem
    SSLCertificateKeyFile /etc/ssl/private/ssl-cert-snakeoil.key
    
    # 日志配置
    ErrorLog \${APACHE_LOG_DIR}/besthammer.club_ssl_error.log
    CustomLog \${APACHE_LOG_DIR}/besthammer.club_ssl_access.log combined
    
    # 安全头
    Header always set X-Content-Type-Options nosniff
    Header always set X-Frame-Options SAMEORIGIN
    Header always set X-XSS-Protection "1; mode=block"
</VirtualHost>
EOF

log_success "Apache虚拟主机配置已重新创建"

echo ""
echo "🔧 第5步：重启Apache并测试配置"
echo "-----------------------------------"

# 测试Apache配置
if apache2ctl configtest; then
    log_success "Apache配置测试通过"
else
    log_error "Apache配置测试失败"
    exit 1
fi

# 重启Apache
systemctl reload apache2
systemctl restart apache2

if systemctl is-active --quiet apache2; then
    log_success "Apache服务重启成功"
else
    log_error "Apache服务重启失败"
    exit 1
fi

echo ""
echo "🔧 第6步：设置正确的文件权限"
echo "-----------------------------------"

# 设置所有者
chown -R www-data:www-data "$PROJECT_DIR"

# 设置目录权限
find "$PROJECT_DIR" -type d -exec chmod 755 {} \;

# 设置文件权限
find "$PROJECT_DIR" -type f -exec chmod 644 {} \;

# 设置特殊权限
chmod -R 775 "$PROJECT_DIR/storage"
chmod -R 775 "$PROJECT_DIR/bootstrap/cache"
chmod 644 "$PROJECT_DIR/.env"

log_success "文件权限设置完成"

echo ""
echo "🔧 第7步：创建简单测试页面"
echo "-----------------------------------"

# 创建简单的PHP测试页面
cat > "$PUBLIC_DIR/test-simple.php" << 'EOF'
<?php
echo "✅ PHP工作正常！<br>";
echo "时间: " . date('Y-m-d H:i:s') . "<br>";
echo "服务器: " . $_SERVER['SERVER_SOFTWARE'] . "<br>";
echo "文档根目录: " . $_SERVER['DOCUMENT_ROOT'] . "<br>";

if (file_exists('index.php')) {
    echo "✅ Laravel入口文件存在<br>";
} else {
    echo "❌ Laravel入口文件不存在<br>";
}

if (is_readable('../.env')) {
    echo "✅ .env文件可读<br>";
} else {
    echo "❌ .env文件不可读<br>";
}
?>
EOF

# 创建静态HTML测试页面
cat > "$PUBLIC_DIR/test-static.html" << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>静态页面测试</title>
</head>
<body>
    <h1>✅ 静态页面工作正常！</h1>
    <p>如果您能看到这个页面，说明Apache虚拟主机配置正确。</p>
    <p><a href="test-simple.php">测试PHP</a></p>
    <p><a href="/">测试Laravel</a></p>
</body>
</html>
EOF

log_success "测试页面创建完成"

echo ""
echo "🔧 第8步：强制重新加载Laravel"
echo "-----------------------------------"

cd "$PROJECT_DIR"

# 重新生成autoload文件
composer dump-autoload --optimize

# 重新生成应用密钥（如果需要）
if ! grep -q "APP_KEY=base64:" .env; then
    php artisan key:generate
fi

# 创建存储链接
php artisan storage:link --force

log_success "Laravel重新加载完成"

echo ""
echo "🎉 精准修复完成！"
echo "=================================="
echo ""
echo "🧪 请按以下顺序测试："
echo ""
echo "1. 静态页面测试："
echo "   https://www.besthammer.club/test-static.html"
echo ""
echo "2. PHP功能测试："
echo "   https://www.besthammer.club/test-simple.php"
echo ""
echo "3. Laravel应用测试："
echo "   https://www.besthammer.club/"
echo ""
echo "4. 多语言路由测试："
echo "   https://www.besthammer.club/en/"
echo ""
echo "📋 如果仍有问题，请检查："
echo "   1. Apache错误日志: tail -f /var/log/apache2/besthammer.club_ssl_error.log"
echo "   2. Laravel日志: tail -f $PROJECT_DIR/storage/logs/laravel.log"
echo "   3. PHP错误日志: tail -f /var/log/php*error.log"
echo ""
echo "🔧 快速调试命令："
echo "   curl -v https://www.besthammer.club/test-static.html"
echo "   curl -v https://www.besthammer.club/test-simple.php"
echo ""
log_info "修复完成，请测试上述URL！"

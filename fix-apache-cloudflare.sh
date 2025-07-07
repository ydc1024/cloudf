#!/bin/bash

# FastPanel + Cloudflare Apache配置修复脚本
# 专门针对Cloudflare代理环境优化

set -e

echo "🌐 开始修复FastPanel + Cloudflare Apache配置..."

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

# 第一步：检查项目结构
log_info "检查项目结构..."

if [ ! -d "$PROJECT_DIR" ]; then
    log_error "项目目录不存在: $PROJECT_DIR"
    exit 1
fi

if [ ! -d "$PUBLIC_DIR" ]; then
    log_error "Laravel public目录不存在: $PUBLIC_DIR"
    exit 1
fi

log_success "项目结构检查通过"

# 第二步：安装Cloudflare IP模块
log_info "配置Cloudflare真实IP检测..."

# 创建Cloudflare IP配置文件
cat > /etc/apache2/conf-available/cloudflare.conf << 'EOF'
# Cloudflare IP范围配置
# 获取访客真实IP地址

# 启用RemoteIP模块
LoadModule remoteip_module modules/mod_remoteip.so

# Cloudflare IPv4 IP范围
RemoteIPTrustedProxy 173.245.48.0/20
RemoteIPTrustedProxy 103.21.244.0/22
RemoteIPTrustedProxy 103.22.200.0/22
RemoteIPTrustedProxy 103.31.4.0/22
RemoteIPTrustedProxy 141.101.64.0/18
RemoteIPTrustedProxy 108.162.192.0/18
RemoteIPTrustedProxy 190.93.240.0/20
RemoteIPTrustedProxy 188.114.96.0/20
RemoteIPTrustedProxy 197.234.240.0/22
RemoteIPTrustedProxy 198.41.128.0/17
RemoteIPTrustedProxy 162.158.0.0/15
RemoteIPTrustedProxy 104.16.0.0/13
RemoteIPTrustedProxy 104.24.0.0/14
RemoteIPTrustedProxy 172.64.0.0/13
RemoteIPTrustedProxy 131.0.72.0/22

# Cloudflare IPv6 IP范围
RemoteIPTrustedProxy 2400:cb00::/32
RemoteIPTrustedProxy 2606:4700::/32
RemoteIPTrustedProxy 2803:f800::/32
RemoteIPTrustedProxy 2405:b500::/32
RemoteIPTrustedProxy 2405:8100::/32
RemoteIPTrustedProxy 2a06:98c0::/29
RemoteIPTrustedProxy 2c0f:f248::/32

# 设置真实IP头
RemoteIPHeader CF-Connecting-IP
RemoteIPHeader X-Forwarded-For
RemoteIPHeader X-Real-IP

# 日志格式包含真实IP
LogFormat "%a %l %u %t \"%r\" %>s %O \"%{Referer}i\" \"%{User-Agent}i\"" cloudflare
EOF

# 启用Cloudflare配置
a2enconf cloudflare
a2enmod remoteip

log_success "Cloudflare IP配置完成"

# 第三步：创建针对Cloudflare优化的虚拟主机配置
log_info "创建Cloudflare优化的Apache虚拟主机配置..."

VHOST_FILE="/etc/apache2/sites-available/besthammer.club.conf"

# 备份现有配置
if [ -f "$VHOST_FILE" ]; then
    cp "$VHOST_FILE" "${VHOST_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
fi

cat > "$VHOST_FILE" << EOF
# Cloudflare代理环境下的虚拟主机配置
<VirtualHost *:80>
    ServerName besthammer.club
    ServerAlias www.besthammer.club
    DocumentRoot $PUBLIC_DIR
    
    # 强制HTTPS重定向（Cloudflare处理SSL）
    RewriteEngine On
    RewriteCond %{HTTP:X-Forwarded-Proto} !https
    RewriteCond %{HTTPS} off
    RewriteRule ^(.*)$ https://%{HTTP_HOST}%{REQUEST_URI} [L,R=301]
    
    <Directory $PUBLIC_DIR>
        AllowOverride All
        Require all granted
        Options -Indexes +FollowSymLinks
        
        # Laravel URL重写规则
        RewriteEngine On
        RewriteCond %{REQUEST_FILENAME} !-f
        RewriteCond %{REQUEST_FILENAME} !-d
        RewriteRule ^(.*)$ index.php [QSA,L]
    </Directory>
    
    # Cloudflare优化的日志格式
    ErrorLog \${APACHE_LOG_DIR}/besthammer.club_error.log
    CustomLog \${APACHE_LOG_DIR}/besthammer.club_access.log cloudflare
    
    # Cloudflare兼容的安全头
    Header always set X-Content-Type-Options nosniff
    Header always set X-Frame-Options SAMEORIGIN
    Header always set X-XSS-Protection "1; mode=block"
    Header always set Referrer-Policy "strict-origin-when-cross-origin"
    
    # 缓存控制（配合Cloudflare）
    <FilesMatch "\.(css|js|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$">
        Header set Cache-Control "public, max-age=31536000"
    </FilesMatch>
</VirtualHost>

<VirtualHost *:443>
    ServerName besthammer.club
    ServerAlias www.besthammer.club
    DocumentRoot $PUBLIC_DIR
    
    <Directory $PUBLIC_DIR>
        AllowOverride All
        Require all granted
        Options -Indexes +FollowSymLinks
        
        # Laravel URL重写规则
        RewriteEngine On
        RewriteCond %{REQUEST_FILENAME} !-f
        RewriteCond %{REQUEST_FILENAME} !-d
        RewriteRule ^(.*)$ index.php [QSA,L]
    </Directory>
    
    # 简化的SSL配置（Cloudflare处理SSL终止）
    # 如果Cloudflare使用"完全"或"完全(严格)"模式，保留SSL配置
    SSLEngine on
    SSLCertificateFile /etc/ssl/certs/ssl-cert-snakeoil.pem
    SSLCertificateKeyFile /etc/ssl/private/ssl-cert-snakeoil.key
    
    # Cloudflare优化的日志格式
    ErrorLog \${APACHE_LOG_DIR}/besthammer.club_ssl_error.log
    CustomLog \${APACHE_LOG_DIR}/besthammer.club_ssl_access.log cloudflare
    
    # Cloudflare兼容的安全头
    Header always set X-Content-Type-Options nosniff
    Header always set X-Frame-Options SAMEORIGIN
    Header always set X-XSS-Protection "1; mode=block"
    Header always set Referrer-Policy "strict-origin-when-cross-origin"
    
    # 缓存控制（配合Cloudflare）
    <FilesMatch "\.(css|js|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$">
        Header set Cache-Control "public, max-age=31536000"
    </FilesMatch>
</VirtualHost>
EOF

log_success "Cloudflare优化的虚拟主机配置创建完成"

# 第四步：启用必要的Apache模块
log_info "启用Apache模块..."

a2enmod rewrite
a2enmod ssl
a2enmod headers
a2enmod remoteip

log_success "Apache模块启用完成"

# 第五步：启用站点
log_info "启用站点配置..."

a2ensite besthammer.club.conf

# 禁用默认站点
if [ -f "/etc/apache2/sites-enabled/000-default.conf" ]; then
    a2dissite 000-default.conf
fi

log_success "站点配置启用完成"

# 第六步：创建Laravel环境优化
log_info "优化Laravel环境配置..."

cd "$PROJECT_DIR"

# 更新.env文件以适配Cloudflare
if [ -f ".env" ]; then
    # 备份.env文件
    cp .env .env.backup.$(date +%Y%m%d_%H%M%S)
    
    # 添加Cloudflare相关配置
    if ! grep -q "CLOUDFLARE_PROXY" .env; then
        cat >> .env << 'EOF'

# Cloudflare代理配置
CLOUDFLARE_PROXY=true
TRUSTED_PROXIES=*
ASSET_URL=https://www.besthammer.club
EOF
    fi
    
    log_success "Laravel环境配置更新完成"
fi

# 第七步：创建Cloudflare测试页面
log_info "创建Cloudflare测试页面..."

cat > "$PUBLIC_DIR/cloudflare-test.php" << 'EOF'
<?php
header('Content-Type: text/html; charset=utf-8');
?>
<!DOCTYPE html>
<html>
<head>
    <title>Cloudflare + FastPanel 配置测试</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; background: #f5f5f5; }
        .container { background: white; padding: 30px; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        .success { color: #28a745; }
        .info { color: #007bff; }
        .warning { color: #ffc107; }
        .error { color: #dc3545; }
        table { width: 100%; border-collapse: collapse; margin: 20px 0; }
        th, td { padding: 10px; text-align: left; border-bottom: 1px solid #ddd; }
        th { background-color: #f8f9fa; }
    </style>
</head>
<body>
    <div class="container">
        <h1 class="success">🌐 Cloudflare + FastPanel 配置测试</h1>
        
        <h2>📡 连接信息</h2>
        <table>
            <tr><th>项目</th><th>值</th><th>状态</th></tr>
            <tr>
                <td>访客IP地址</td>
                <td><?php echo $_SERVER['REMOTE_ADDR'] ?? 'N/A'; ?></td>
                <td class="<?php echo isset($_SERVER['HTTP_CF_CONNECTING_IP']) ? 'success' : 'warning'; ?>">
                    <?php echo isset($_SERVER['HTTP_CF_CONNECTING_IP']) ? '✅ Cloudflare代理' : '⚠️ 直连'; ?>
                </td>
            </tr>
            <tr>
                <td>真实IP (CF-Connecting-IP)</td>
                <td><?php echo $_SERVER['HTTP_CF_CONNECTING_IP'] ?? 'N/A'; ?></td>
                <td class="<?php echo isset($_SERVER['HTTP_CF_CONNECTING_IP']) ? 'success' : 'error'; ?>">
                    <?php echo isset($_SERVER['HTTP_CF_CONNECTING_IP']) ? '✅ 检测到' : '❌ 未检测到'; ?>
                </td>
            </tr>
            <tr>
                <td>协议</td>
                <td><?php echo ($_SERVER['HTTPS'] ?? 'off') === 'on' ? 'HTTPS' : 'HTTP'; ?></td>
                <td class="<?php echo ($_SERVER['HTTPS'] ?? 'off') === 'on' ? 'success' : 'warning'; ?>">
                    <?php echo ($_SERVER['HTTPS'] ?? 'off') === 'on' ? '✅ 安全连接' : '⚠️ 非安全连接'; ?>
                </td>
            </tr>
            <tr>
                <td>X-Forwarded-Proto</td>
                <td><?php echo $_SERVER['HTTP_X_FORWARDED_PROTO'] ?? 'N/A'; ?></td>
                <td class="info">Cloudflare协议头</td>
            </tr>
        </table>
        
        <h2>🔍 Cloudflare检测</h2>
        <table>
            <tr><th>Cloudflare头</th><th>值</th></tr>
            <tr><td>CF-Ray</td><td><?php echo $_SERVER['HTTP_CF_RAY'] ?? 'N/A'; ?></td></tr>
            <tr><td>CF-Visitor</td><td><?php echo $_SERVER['HTTP_CF_VISITOR'] ?? 'N/A'; ?></td></tr>
            <tr><td>CF-Country</td><td><?php echo $_SERVER['HTTP_CF_IPCOUNTRY'] ?? 'N/A'; ?></td></tr>
        </table>
        
        <h2>🚀 Laravel测试</h2>
        <p>
            <a href="/" class="info">🏠 Laravel首页</a> | 
            <a href="/en/" class="info">🇺🇸 英语版本</a> | 
            <a href="/es/" class="info">🇪🇸 西班牙语版本</a>
        </p>
        
        <hr>
        <p><small>测试时间: <?php echo date('Y-m-d H:i:s T'); ?></small></p>
        <p><small>服务器: <?php echo $_SERVER['SERVER_SOFTWARE'] ?? 'Unknown'; ?></small></p>
    </div>
</body>
</html>
EOF

log_success "Cloudflare测试页面创建完成"

# 第八步：测试Apache配置
log_info "测试Apache配置..."

if apache2ctl configtest; then
    log_success "Apache配置测试通过"
else
    log_error "Apache配置测试失败"
    exit 1
fi

# 第九步：重启Apache
log_info "重启Apache服务..."

systemctl reload apache2
systemctl restart apache2

if systemctl is-active --quiet apache2; then
    log_success "Apache服务重启成功"
else
    log_error "Apache服务重启失败"
    exit 1
fi

# 第十步：设置文件权限
log_info "设置文件权限..."

APACHE_USER="www-data"
chown -R $APACHE_USER:$APACHE_USER "$PROJECT_DIR"
chmod -R 755 "$PROJECT_DIR"
chmod -R 775 "$PROJECT_DIR/storage"
chmod -R 775 "$PROJECT_DIR/bootstrap/cache"

log_success "文件权限设置完成"

echo ""
log_success "🎉 Cloudflare + FastPanel配置完成！"
echo ""
echo "📋 配置摘要:"
echo "   虚拟主机配置: $VHOST_FILE"
echo "   文档根目录: $PUBLIC_DIR"
echo "   Cloudflare IP检测: 已启用"
echo "   真实IP获取: CF-Connecting-IP"
echo ""
echo "🧪 测试URL:"
echo "   Cloudflare测试: https://www.besthammer.club/cloudflare-test.php"
echo "   Laravel首页: https://www.besthammer.club/"
echo "   多语言测试: https://www.besthammer.club/en/"
echo ""
echo "☁️ Cloudflare设置建议:"
echo "   1. SSL/TLS模式: 完全 或 完全(严格)"
echo "   2. 缓存级别: 标准"
echo "   3. 开发模式: 测试时可临时开启"
echo "   4. 页面规则: 可设置缓存规则"
echo ""
echo "🔍 如果仍有问题，请检查："
echo "   1. Cloudflare DNS设置（橙色云朵=代理开启）"
echo "   2. Apache日志: tail -f /var/log/apache2/besthammer.club_error.log"
echo "   3. Laravel日志: tail -f $PROJECT_DIR/storage/logs/laravel.log"
echo ""
log_info "请访问Cloudflare测试页面验证配置！"

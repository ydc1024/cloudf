#!/bin/bash

# Cloudflare + FastPanel 架构专用修复脚本
# 针对域名在Cloudflare托管，服务器使用FastPanel的情况

set -e

echo "☁️ Cloudflare + FastPanel 架构修复脚本"
echo "========================================"
echo "架构：用户 → Cloudflare → FastPanel服务器 → Laravel"
echo "域名DNS：Cloudflare管理"
echo "服务器：FastPanel管理"
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

log_step "第1步：分析当前架构"
echo "-----------------------------------"

# 获取服务器IP
SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || curl -s ipinfo.io/ip 2>/dev/null || echo "未知")
log_info "服务器IP: $SERVER_IP"

# 检查Cloudflare是否指向此服务器
log_info "检查Cloudflare DNS配置..."
DOMAIN_IP=$(nslookup www.besthammer.club 8.8.8.8 2>/dev/null | grep 'Address:' | tail -1 | awk '{print $2}' || echo "解析失败")
log_info "域名解析IP: $DOMAIN_IP"

if [ "$DOMAIN_IP" != "$SERVER_IP" ] && [ "$DOMAIN_IP" != "解析失败" ]; then
    log_warning "域名IP与服务器IP不匹配，这是正常的（Cloudflare代理）"
else
    log_info "IP配置检查完成"
fi

log_step "第2步：检查FastPanel默认配置"
echo "-----------------------------------"

# 查找FastPanel的默认虚拟主机配置
DEFAULT_CONFIGS=(
    "/etc/apache2/sites-available/000-default.conf"
    "/etc/apache2/sites-available/default-ssl.conf"
    "/etc/apache2/sites-available/fastpanel-default.conf"
)

ACTIVE_DEFAULT=""
for config in "${DEFAULT_CONFIGS[@]}"; do
    if [ -f "$config" ] && [ -L "/etc/apache2/sites-enabled/$(basename $config)" ]; then
        ACTIVE_DEFAULT="$config"
        log_info "发现活跃的默认配置: $config"
        break
    fi
done

log_step "第3步：创建Cloudflare兼容的虚拟主机配置"
echo "-----------------------------------"

# 创建专门的配置文件
CLOUDFLARE_CONFIG="/etc/apache2/sites-available/cloudflare-besthammer.conf"

# 备份现有配置
if [ -f "$CLOUDFLARE_CONFIG" ]; then
    cp "$CLOUDFLARE_CONFIG" "${CLOUDFLARE_CONFIG}.backup.$(date +%Y%m%d_%H%M%S)"
fi

cat > "$CLOUDFLARE_CONFIG" << EOF
# Cloudflare + FastPanel 专用虚拟主机配置
# 处理来自Cloudflare的代理请求

# HTTP虚拟主机 (处理Cloudflare的HTTP请求)
<VirtualHost *:80>
    # 接受所有域名请求（因为Cloudflare会转发）
    ServerName besthammer.club
    ServerAlias www.besthammer.club
    ServerAlias $SERVER_IP
    
    DocumentRoot $PUBLIC_DIR
    
    # Cloudflare真实IP配置
    RemoteIPHeader CF-Connecting-IP
    RemoteIPHeader X-Forwarded-For
    
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
    
    # 强制HTTPS重定向（检查Cloudflare头）
    RewriteEngine On
    RewriteCond %{HTTP:X-Forwarded-Proto} !https
    RewriteCond %{HTTP:CF-Visitor} !"scheme":"https"
    RewriteRule ^(.*)$ https://%{HTTP_HOST}%{REQUEST_URI} [L,R=301]
    
    # 日志
    ErrorLog /var/log/apache2/cloudflare_error.log
    CustomLog /var/log/apache2/cloudflare_access.log combined
</VirtualHost>

# HTTPS虚拟主机 (处理Cloudflare的HTTPS请求)
<VirtualHost *:443>
    # 接受所有域名请求
    ServerName besthammer.club
    ServerAlias www.besthammer.club
    ServerAlias $SERVER_IP
    
    DocumentRoot $PUBLIC_DIR
    
    # Cloudflare真实IP配置
    RemoteIPHeader CF-Connecting-IP
    RemoteIPHeader X-Forwarded-For
    
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
    
    # SSL配置（自签名证书，因为Cloudflare处理真正的SSL）
    SSLEngine on
    SSLCertificateFile /etc/ssl/certs/ssl-cert-snakeoil.pem
    SSLCertificateKeyFile /etc/ssl/private/ssl-cert-snakeoil.key
    
    # Cloudflare兼容头
    Header always set X-Content-Type-Options nosniff
    Header always set X-Frame-Options SAMEORIGIN
    Header always set X-XSS-Protection "1; mode=block"
    
    # 日志
    ErrorLog /var/log/apache2/cloudflare_ssl_error.log
    CustomLog /var/log/apache2/cloudflare_ssl_access.log combined
</VirtualHost>

# 默认虚拟主机（捕获所有其他请求）
<VirtualHost *:80>
    ServerName _default_
    DocumentRoot $PUBLIC_DIR
    
    <Directory $PUBLIC_DIR>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
        
        RewriteEngine On
        RewriteCond %{REQUEST_FILENAME} !-f
        RewriteCond %{REQUEST_FILENAME} !-d
        RewriteRule ^(.*)$ index.php [QSA,L]
    </Directory>
</VirtualHost>

<VirtualHost *:443>
    ServerName _default_
    DocumentRoot $PUBLIC_DIR
    
    SSLEngine on
    SSLCertificateFile /etc/ssl/certs/ssl-cert-snakeoil.pem
    SSLCertificateKeyFile /etc/ssl/private/ssl-cert-snakeoil.key
    
    <Directory $PUBLIC_DIR>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
        
        RewriteEngine On
        RewriteCond %{REQUEST_FILENAME} !-f
        RewriteCond %{REQUEST_FILENAME} !-d
        RewriteRule ^(.*)$ index.php [QSA,L]
    </Directory>
</VirtualHost>
EOF

log_success "Cloudflare兼容配置创建完成"

log_step "第4步：配置Cloudflare IP信任"
echo "-----------------------------------"

# 更新Cloudflare IP配置
cat > /etc/apache2/conf-available/cloudflare-ips.conf << 'EOF'
# Cloudflare IP范围 - 2024年更新
LoadModule remoteip_module modules/mod_remoteip.so

# Cloudflare IPv4 ranges
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

# Cloudflare IPv6 ranges
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
EOF

# 启用配置
a2enconf cloudflare-ips

log_step "第5步：禁用冲突配置，启用新配置"
echo "-----------------------------------"

# 禁用可能冲突的默认站点
if [ -f "/etc/apache2/sites-enabled/000-default.conf" ]; then
    a2dissite 000-default.conf
    log_info "已禁用默认HTTP站点"
fi

if [ -f "/etc/apache2/sites-enabled/default-ssl.conf" ]; then
    a2dissite default-ssl.conf
    log_info "已禁用默认SSL站点"
fi

# 启用我们的Cloudflare配置
a2ensite cloudflare-besthammer.conf
log_success "已启用Cloudflare专用配置"

# 启用必要模块
a2enmod rewrite ssl headers remoteip

log_step "第6步：创建架构测试页面"
echo "-----------------------------------"

cat > "$PUBLIC_DIR/architecture-test.php" << 'EOF'
<?php
header('Content-Type: text/html; charset=utf-8');
?>
<!DOCTYPE html>
<html>
<head>
    <title>Cloudflare + FastPanel 架构测试</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background: #f0f8ff; }
        .container { background: white; padding: 30px; border-radius: 10px; box-shadow: 0 4px 6px rgba(0,0,0,0.1); }
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
    </style>
</head>
<body>
    <div class="container">
        <h1>☁️ Cloudflare + FastPanel 架构测试</h1>
        
        <h2>🌐 请求路径分析</h2>
        <table>
            <tr><th>步骤</th><th>组件</th><th>状态</th><th>详情</th></tr>
            <tr class="<?php echo isset($_SERVER['HTTP_CF_RAY']) ? 'status-ok' : 'status-error'; ?>">
                <td>1</td>
                <td>Cloudflare代理</td>
                <td><?php echo isset($_SERVER['HTTP_CF_RAY']) ? '✅ 正常' : '❌ 异常'; ?></td>
                <td><?php echo $_SERVER['HTTP_CF_RAY'] ?? '未检测到CF-Ray头'; ?></td>
            </tr>
            <tr class="status-ok">
                <td>2</td>
                <td>FastPanel服务器</td>
                <td>✅ 正常</td>
                <td><?php echo $_SERVER['SERVER_SOFTWARE']; ?></td>
            </tr>
            <tr class="<?php echo file_exists('index.php') ? 'status-ok' : 'status-error'; ?>">
                <td>3</td>
                <td>Laravel应用</td>
                <td><?php echo file_exists('index.php') ? '✅ 正常' : '❌ 异常'; ?></td>
                <td><?php echo file_exists('index.php') ? 'Laravel入口文件存在' : 'Laravel入口文件缺失'; ?></td>
            </tr>
        </table>
        
        <h2>📡 网络信息</h2>
        <table>
            <tr><th>项目</th><th>值</th><th>说明</th></tr>
            <tr>
                <td>访客IP (原始)</td>
                <td><?php echo $_SERVER['REMOTE_ADDR']; ?></td>
                <td class="info">Apache看到的IP</td>
            </tr>
            <tr>
                <td>访客IP (真实)</td>
                <td><?php echo $_SERVER['HTTP_CF_CONNECTING_IP'] ?? '未获取'; ?></td>
                <td class="info">Cloudflare提供的真实IP</td>
            </tr>
            <tr>
                <td>协议</td>
                <td><?php echo isset($_SERVER['HTTPS']) && $_SERVER['HTTPS'] === 'on' ? 'HTTPS' : 'HTTP'; ?></td>
                <td class="info">当前连接协议</td>
            </tr>
            <tr>
                <td>X-Forwarded-Proto</td>
                <td><?php echo $_SERVER['HTTP_X_FORWARDED_PROTO'] ?? '未设置'; ?></td>
                <td class="info">Cloudflare转发协议</td>
            </tr>
        </table>
        
        <h2>🏗️ 服务器架构</h2>
        <table>
            <tr><th>组件</th><th>配置</th><th>状态</th></tr>
            <tr>
                <td>文档根目录</td>
                <td><?php echo $_SERVER['DOCUMENT_ROOT']; ?></td>
                <td class="<?php echo strpos($_SERVER['DOCUMENT_ROOT'], '/public') !== false ? 'success' : 'warning'; ?>">
                    <?php echo strpos($_SERVER['DOCUMENT_ROOT'], '/public') !== false ? '✅ 正确' : '⚠️ 检查'; ?>
                </td>
            </tr>
            <tr>
                <td>服务器名称</td>
                <td><?php echo $_SERVER['SERVER_NAME']; ?></td>
                <td class="info">虚拟主机配置</td>
            </tr>
            <tr>
                <td>HTTP主机</td>
                <td><?php echo $_SERVER['HTTP_HOST']; ?></td>
                <td class="info">请求主机头</td>
            </tr>
        </table>
        
        <h2>🧪 功能测试</h2>
        <div style="margin: 20px 0;">
            <a href="/" style="display: inline-block; margin: 5px; padding: 10px 15px; background: #007bff; color: white; text-decoration: none; border-radius: 5px;">🏠 Laravel首页</a>
            <a href="/en/" style="display: inline-block; margin: 5px; padding: 10px 15px; background: #28a745; color: white; text-decoration: none; border-radius: 5px;">🇺🇸 英语版本</a>
            <a href="<?php echo $_SERVER['PHP_SELF']; ?>" style="display: inline-block; margin: 5px; padding: 10px 15px; background: #6c757d; color: white; text-decoration: none; border-radius: 5px;">🔄 刷新测试</a>
        </div>
        
        <hr style="margin: 30px 0;">
        <p><small>
            <strong>架构说明：</strong> 
            用户 → Cloudflare代理 → FastPanel服务器(<?php echo $_SERVER['SERVER_ADDR'] ?? '未知IP'; ?>) → Laravel应用<br>
            <strong>测试时间：</strong> <?php echo date('Y-m-d H:i:s T'); ?>
        </small></p>
    </div>
</body>
</html>
EOF

log_success "架构测试页面创建完成"

log_step "第7步：重启服务并设置权限"
echo "-----------------------------------"

# 测试Apache配置
if apache2ctl configtest; then
    log_success "Apache配置测试通过"
else
    log_error "Apache配置有错误"
    apache2ctl configtest
    exit 1
fi

# 设置文件权限
chown -R www-data:www-data "$PROJECT_DIR"
chmod -R 755 "$PROJECT_DIR"
chmod -R 775 "$PROJECT_DIR/storage"
chmod -R 775 "$PROJECT_DIR/bootstrap/cache"

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
echo "🎉 Cloudflare + FastPanel 架构配置完成！"
echo "=========================================="
echo ""
echo "🧪 请按以下顺序测试："
echo ""
echo "1. 架构测试页面（最重要）："
echo "   https://www.besthammer.club/architecture-test.php"
echo ""
echo "2. Laravel应用测试："
echo "   https://www.besthammer.club/"
echo ""
echo "3. 多语言路由测试："
echo "   https://www.besthammer.club/en/"
echo ""
echo "📋 架构说明："
echo "   用户浏览器 → Cloudflare代理 → 您的服务器($SERVER_IP) → Laravel应用"
echo ""
echo "☁️ Cloudflare设置确认："
echo "   □ DNS A记录指向服务器IP: $SERVER_IP"
echo "   □ 代理状态：开启（橙色云朵）"
echo "   □ SSL/TLS模式：完全 或 完全(严格)"
echo ""
echo "🔍 如果架构测试页面正常显示，说明配置成功！"
echo "   如果仍有问题，请检查Cloudflare的DNS和代理设置。"
echo ""
log_info "Cloudflare + FastPanel 架构配置完成！"

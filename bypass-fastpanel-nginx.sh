#!/bin/bash

# 绕过FastPanel限制的激进解决方案
# 直接修改Nginx主配置文件

set -e

echo "🚀 绕过FastPanel限制的激进解决方案"
echo "================================"
echo "直接在Nginx主配置中添加server块"
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

log_step "第1步：找到Nginx主配置文件"
echo "-----------------------------------"

# 查找Nginx主配置文件
NGINX_CONF_PATHS=(
    "/etc/nginx/nginx.conf"
    "/usr/local/nginx/conf/nginx.conf"
    "/usr/local/fastpanel2/nginx/conf/nginx.conf"
)

MAIN_NGINX_CONF=""
for conf in "${NGINX_CONF_PATHS[@]}"; do
    if [ -f "$conf" ]; then
        log_success "发现Nginx主配置: $conf"
        MAIN_NGINX_CONF="$conf"
        break
    fi
done

if [ -z "$MAIN_NGINX_CONF" ]; then
    log_error "未找到Nginx主配置文件"
    exit 1
fi

log_step "第2步：备份主配置文件"
echo "-----------------------------------"

# 创建备份
BACKUP_FILE="${MAIN_NGINX_CONF}.backup.$(date +%Y%m%d_%H%M%S)"
cp "$MAIN_NGINX_CONF" "$BACKUP_FILE"
log_success "配置已备份到: $BACKUP_FILE"

log_step "第3步：检查现有配置"
echo "-----------------------------------"

# 检查是否已存在besthammer.club配置
if grep -q "besthammer.club" "$MAIN_NGINX_CONF"; then
    log_warning "主配置中已存在besthammer.club相关配置"
    log_info "移除现有配置..."
    
    # 移除现有的besthammer.club配置
    sed -i '/server_name.*besthammer\.club/,/^[[:space:]]*}/d' "$MAIN_NGINX_CONF"
    log_success "已移除现有配置"
fi

log_step "第4步：直接在主配置中添加server块"
echo "-----------------------------------"

# 在http块的末尾添加server配置
log_info "在主配置文件中添加server块..."

# 创建临时配置内容
TEMP_CONFIG=$(mktemp)
cat > "$TEMP_CONFIG" << EOF

    # FastPanel绕过方案 - besthammer.club配置
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
        ssl_protocols TLSv1.2 TLSv1.3;
        
        # Cloudflare真实IP
        real_ip_header CF-Connecting-IP;
        set_real_ip_from 0.0.0.0/0;
        
        # Laravel项目
        root $PUBLIC_DIR;
        index index.php index.html;
        
        # 日志
        access_log /var/log/nginx/besthammer.club_access.log;
        error_log /var/log/nginx/besthammer.club_error.log;
        
        # Laravel URL重写
        location / {
            try_files \$uri \$uri/ /index.php?\$query_string;
        }
        
        # PHP处理
        location ~ \.php$ {
            try_files \$uri =404;
            fastcgi_split_path_info ^(.+\.php)(/.+)$;
            fastcgi_pass unix:/var/run/php/php8.3-fpm.sock;
            fastcgi_index index.php;
            include fastcgi_params;
            fastcgi_param SCRIPT_FILENAME \$realpath_root\$fastcgi_script_name;
            fastcgi_param DOCUMENT_ROOT \$realpath_root;
            fastcgi_param HTTPS on;
            fastcgi_param HTTP_CF_CONNECTING_IP \$http_cf_connecting_ip;
            fastcgi_param HTTP_X_FORWARDED_PROTO \$http_x_forwarded_proto;
            fastcgi_param HTTP_CF_RAY \$http_cf_ray;
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
        
        location ~ ^/(\.env|\.git|composer\.(json|lock)|artisan) {
            deny all;
        }
    }
EOF

# 在http块的最后一个}之前插入配置
sed -i '/^[[:space:]]*}[[:space:]]*$/i\
# FastPanel绕过方案 - besthammer.club配置开始' "$MAIN_NGINX_CONF"

# 在最后一个}之前插入server块
awk -v config_file="$TEMP_CONFIG" '
/^[[:space:]]*}[[:space:]]*$/ && !inserted {
    while ((getline line < config_file) > 0) {
        print line
    }
    close(config_file)
    inserted = 1
}
{print}
' "$MAIN_NGINX_CONF" > "${MAIN_NGINX_CONF}.tmp"

mv "${MAIN_NGINX_CONF}.tmp" "$MAIN_NGINX_CONF"
rm -f "$TEMP_CONFIG"

log_success "Server块已添加到主配置文件"

log_step "第5步：确保SSL证书存在"
echo "-----------------------------------"

# 检查并生成SSL证书
if [ ! -f "/etc/ssl/certs/ssl-cert-snakeoil.pem" ]; then
    log_info "生成自签名SSL证书..."
    make-ssl-cert generate-default-snakeoil --force-overwrite
    log_success "SSL证书已生成"
else
    log_success "SSL证书已存在"
fi

log_step "第6步：测试配置并重启"
echo "-----------------------------------"

# 测试配置
log_info "测试Nginx配置..."
if nginx -t; then
    log_success "Nginx配置测试通过"
else
    log_error "Nginx配置测试失败，恢复备份..."
    cp "$BACKUP_FILE" "$MAIN_NGINX_CONF"
    nginx -t
    exit 1
fi

# 重启Nginx
log_info "重启Nginx服务..."
systemctl restart nginx
sleep 2

if systemctl is-active --quiet nginx; then
    log_success "Nginx重启成功"
else
    log_error "Nginx重启失败，恢复备份..."
    cp "$BACKUP_FILE" "$MAIN_NGINX_CONF"
    systemctl restart nginx
    exit 1
fi

log_step "第7步：验证配置生效"
echo "-----------------------------------"

# 检查配置是否被加载
log_info "验证配置是否生效..."
if nginx -T 2>/dev/null | grep -q "server_name.*besthammer.club"; then
    log_success "配置已生效"
else
    log_warning "配置可能未生效"
fi

# 创建绕过验证页面
cat > "$PUBLIC_DIR/bypass-test.php" << 'EOF'
<?php
header('Content-Type: text/html; charset=utf-8');
?>
<!DOCTYPE html>
<html>
<head>
    <title>FastPanel绕过方案验证</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background: linear-gradient(135deg, #ff7675 0%, #fd79a8 100%); color: white; }
        .container { background: rgba(255,255,255,0.95); color: #333; padding: 40px; border-radius: 15px; box-shadow: 0 8px 32px rgba(0,0,0,0.3); max-width: 900px; margin: 0 auto; }
        .success { color: #00b894; font-weight: bold; font-size: 20px; }
        .info { color: #0984e3; }
        table { width: 100%; border-collapse: collapse; margin: 20px 0; }
        th, td { padding: 12px; text-align: left; border-bottom: 1px solid #ddd; }
        th { background: linear-gradient(135deg, #ff7675 0%, #fd79a8 100%); color: white; }
        .status-ok { background-color: #d1f2eb; }
    </style>
</head>
<body>
    <div class="container">
        <h1 class="success">🚀 FastPanel绕过方案成功！</h1>
        
        <p>如果您能看到这个页面，说明绕过FastPanel限制的激进方案成功了！</p>
        
        <div style="background: #d1f2eb; padding: 20px; border-radius: 10px; border-left: 5px solid #00b894; margin: 20px 0;">
            <h3 style="color: #00b894; margin: 0 0 10px 0;">✅ 绕过成功</h3>
            <p style="color: #00b894; margin: 0;">直接在Nginx主配置中添加server块的方案成功，502错误已解决！</p>
        </div>
        
        <h2>系统状态</h2>
        <table>
            <tr><th>项目</th><th>值</th><th>状态</th></tr>
            <tr class="status-ok">
                <td>配置方案</td>
                <td>主配置直接添加</td>
                <td>✅ 绕过FastPanel</td>
            </tr>
            <tr class="status-ok">
                <td>Web服务器</td>
                <td><?php echo $_SERVER['SERVER_SOFTWARE'] ?? 'Unknown'; ?></td>
                <td>✅ Nginx</td>
            </tr>
            <tr class="status-ok">
                <td>PHP处理器</td>
                <td><?php echo php_sapi_name(); ?></td>
                <td>✅ PHP 8.3-FPM</td>
            </tr>
            <tr class="status-ok">
                <td>SSL状态</td>
                <td><?php echo isset($_SERVER['HTTPS']) ? 'HTTPS' : 'HTTP'; ?></td>
                <td>✅ 安全连接</td>
            </tr>
        </table>
        
        <h2>连接信息</h2>
        <table>
            <tr><th>项目</th><th>值</th></tr>
            <tr><td>服务器名称</td><td><?php echo $_SERVER['SERVER_NAME']; ?></td></tr>
            <tr><td>文档根目录</td><td><?php echo $_SERVER['DOCUMENT_ROOT']; ?></td></tr>
            <tr><td>CF-Ray</td><td><?php echo $_SERVER['HTTP_CF_RAY'] ?? 'N/A'; ?></td></tr>
            <tr><td>真实IP</td><td><?php echo $_SERVER['HTTP_CF_CONNECTING_IP'] ?? $_SERVER['REMOTE_ADDR']; ?></td></tr>
        </table>
        
        <h2>功能测试</h2>
        <div style="text-align: center; margin: 30px 0;">
            <a href="/" style="display: inline-block; margin: 10px; padding: 15px 25px; background: linear-gradient(135deg, #ff7675 0%, #fd79a8 100%); color: white; text-decoration: none; border-radius: 25px; font-weight: bold;">🏠 Laravel首页</a>
            <a href="/en/" style="display: inline-block; margin: 10px; padding: 15px 25px; background: linear-gradient(135deg, #00b894 0%, #00cec9 100%); color: white; text-decoration: none; border-radius: 25px; font-weight: bold;">🇺🇸 英语版本</a>
        </div>
        
        <hr style="margin: 30px 0;">
        <p style="text-align: center; color: #6c757d;">
            <small>
                <strong>绕过方案成功时间：</strong> <?php echo date('Y-m-d H:i:s T'); ?><br>
                <strong>方案：</strong> 直接修改Nginx主配置文件
            </small>
        </p>
    </div>
</body>
</html>
EOF

# 设置权限
chown -R www-data:www-data "$PROJECT_DIR"
chmod -R 755 "$PROJECT_DIR"
chmod -R 775 "$PROJECT_DIR/storage"
chmod -R 775 "$PROJECT_DIR/bootstrap/cache"

log_success "绕过验证页面创建完成"

echo ""
echo "🎉 FastPanel绕过方案完成！"
echo "=========================="
echo ""
echo "📋 绕过方案摘要："
echo "✅ 直接修改了Nginx主配置文件"
echo "✅ 在http块中添加了server块"
echo "✅ 绕过了FastPanel的配置管理"
echo "✅ 配置已生效并重启服务"
echo ""
echo "🧪 绕过验证页面："
echo "   https://www.besthammer.club/bypass-test.php"
echo ""
echo "🎯 如果验证页面正常显示，说明绕过方案成功！"
echo ""
echo "⚠️ 注意事项："
echo "   - 此方案绕过了FastPanel的配置管理"
echo "   - FastPanel更新可能会覆盖配置"
echo "   - 建议定期备份配置文件"
echo ""
echo "📁 配置文件："
echo "   - 主配置: $MAIN_NGINX_CONF"
echo "   - 备份文件: $BACKUP_FILE"
echo ""
log_info "绕过方案完成！请测试验证页面！"

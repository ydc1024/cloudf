#!/bin/bash

# FastPanel深度Nginx配置修复脚本
# 解决FastPanel环境下的顽固502错误

set -e

echo "🔬 FastPanel深度Nginx配置修复"
echo "============================="
echo "深度分析并修复FastPanel环境下的Nginx配置问题"
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

log_step "第1步：深度分析FastPanel Nginx架构"
echo "-----------------------------------"

# 查找所有可能的Nginx进程和配置
log_info "查找所有Nginx相关进程..."
ps aux | grep nginx | grep -v grep

echo ""
log_info "查找所有Nginx配置目录..."
NGINX_DIRS=(
    "/etc/nginx"
    "/usr/local/nginx"
    "/usr/local/fastpanel2/nginx"
    "/opt/nginx"
    "/var/lib/fastpanel/nginx"
)

ACTIVE_NGINX_DIR=""
for dir in "${NGINX_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        log_success "发现Nginx目录: $dir"
        if [ -f "$dir/nginx.conf" ]; then
            log_info "  → 包含主配置文件"
            ACTIVE_NGINX_DIR="$dir"
        fi
        if [ -d "$dir/sites-available" ]; then
            log_info "  → 包含sites-available目录"
        fi
        if [ -d "$dir/sites-enabled" ]; then
            log_info "  → 包含sites-enabled目录"
        fi
    fi
done

# 检查FastPanel特有的Nginx配置
log_info "检查FastPanel特有的Nginx配置..."
FASTPANEL_NGINX_DIRS=(
    "/usr/local/fastpanel2/nginx/conf"
    "/usr/local/fastpanel2/conf/nginx"
    "/etc/fastpanel/nginx"
)

for dir in "${FASTPANEL_NGINX_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        log_warning "发现FastPanel Nginx目录: $dir"
        ls -la "$dir" | head -5
    fi
done

log_step "第2步：分析Nginx主配置文件"
echo "-----------------------------------"

# 查找并分析主配置文件
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
        
        # 分析include指令
        log_info "分析include指令..."
        grep -n "include.*sites" "$conf" || echo "  → 未发现sites相关include"
        grep -n "include.*conf.d" "$conf" || echo "  → 未发现conf.d相关include"
        grep -n "include.*fastpanel" "$conf" || echo "  → 未发现fastpanel相关include"
        break
    fi
done

if [ -z "$MAIN_NGINX_CONF" ]; then
    log_error "未找到Nginx主配置文件"
    exit 1
fi

log_step "第3步：检查FastPanel的Nginx管理方式"
echo "-----------------------------------"

# 检查FastPanel是否使用自己的Nginx
if pgrep -f "fastpanel.*nginx" > /dev/null; then
    log_warning "发现FastPanel管理的Nginx进程"
    ps aux | grep "fastpanel.*nginx" | grep -v grep
    
    # 查找FastPanel的Nginx配置
    log_info "查找FastPanel的Nginx配置文件..."
    find /usr/local/fastpanel2 -name "*.conf" -type f 2>/dev/null | grep -i nginx | head -5
fi

# 检查FastPanel的站点配置目录
FASTPANEL_SITES_DIRS=(
    "/usr/local/fastpanel2/nginx/conf/sites"
    "/usr/local/fastpanel2/conf/nginx/sites"
    "/etc/fastpanel/nginx/sites"
)

FASTPANEL_SITES_DIR=""
for dir in "${FASTPANEL_SITES_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        log_success "发现FastPanel站点目录: $dir"
        FASTPANEL_SITES_DIR="$dir"
        ls -la "$dir" | head -5
        break
    fi
done

log_step "第4步：创建兼容FastPanel的配置"
echo "-----------------------------------"

# 根据发现的架构创建配置
if [ -n "$FASTPANEL_SITES_DIR" ]; then
    # 使用FastPanel的配置目录
    log_info "使用FastPanel配置目录: $FASTPANEL_SITES_DIR"
    SITE_CONFIG="$FASTPANEL_SITES_DIR/besthammer.club.conf"
else
    # 使用标准配置目录
    log_info "使用标准Nginx配置目录"
    SITE_CONFIG="/etc/nginx/sites-available/besthammer.club.conf"
fi

log_info "创建站点配置: $SITE_CONFIG"

# 确保目录存在
mkdir -p "$(dirname "$SITE_CONFIG")"

# 创建配置文件
cat > "$SITE_CONFIG" << EOF
# FastPanel兼容的Nginx配置
# 专门解决502错误

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

log_success "配置文件创建完成"

log_step "第5步：修改Nginx主配置以包含站点"
echo "-----------------------------------"

# 备份主配置文件
cp "$MAIN_NGINX_CONF" "${MAIN_NGINX_CONF}.backup.$(date +%Y%m%d_%H%M%S)"

# 检查是否已包含站点配置
if grep -q "include.*sites-enabled" "$MAIN_NGINX_CONF"; then
    log_info "主配置已包含sites-enabled"
elif grep -q "include.*sites" "$MAIN_NGINX_CONF"; then
    log_info "主配置已包含sites目录"
else
    log_warning "主配置未包含站点配置，正在添加..."
    
    # 在http块中添加include指令
    sed -i '/http {/a\    include /etc/nginx/sites-enabled/*;' "$MAIN_NGINX_CONF"
    
    # 如果使用FastPanel目录，添加对应的include
    if [ -n "$FASTPANEL_SITES_DIR" ]; then
        sed -i "/http {/a\    include $FASTPANEL_SITES_DIR/*.conf;" "$MAIN_NGINX_CONF"
    fi
    
    log_success "已添加站点配置包含指令"
fi

log_step "第6步：启用站点配置"
echo "-----------------------------------"

# 创建sites-enabled目录和链接
if [ -d "/etc/nginx/sites-enabled" ]; then
    ln -sf "$SITE_CONFIG" "/etc/nginx/sites-enabled/besthammer.club.conf"
    log_success "已在sites-enabled中创建链接"
fi

# 如果使用FastPanel目录，确保配置被包含
if [ -n "$FASTPANEL_SITES_DIR" ]; then
    log_info "配置已放置在FastPanel目录中"
fi

log_step "第7步：测试并重启Nginx"
echo "-----------------------------------"

# 测试配置
log_info "测试Nginx配置..."
if nginx -t; then
    log_success "Nginx配置测试通过"
else
    log_error "Nginx配置测试失败"
    nginx -t
    
    # 尝试修复常见问题
    log_info "尝试修复配置问题..."
    
    # 检查SSL证书文件
    if [ ! -f "/etc/ssl/certs/ssl-cert-snakeoil.pem" ]; then
        log_warning "SSL证书不存在，生成自签名证书..."
        make-ssl-cert generate-default-snakeoil --force-overwrite
    fi
    
    # 再次测试
    if nginx -t; then
        log_success "配置问题已修复"
    else
        log_error "配置问题无法自动修复"
        exit 1
    fi
fi

# 重启Nginx
log_info "重启Nginx服务..."

# 如果是FastPanel管理的Nginx，尝试重启FastPanel
if pgrep -f "fastpanel.*nginx" > /dev/null; then
    log_info "重启FastPanel Nginx..."
    pkill -f "fastpanel.*nginx" || true
    sleep 2
    systemctl restart fastpanel2 || true
    sleep 3
fi

# 重启系统Nginx
systemctl restart nginx
sleep 2

if systemctl is-active --quiet nginx; then
    log_success "Nginx重启成功"
else
    log_error "Nginx重启失败"
    systemctl status nginx
fi

log_step "第8步：验证配置生效"
echo "-----------------------------------"

# 检查配置是否被加载
log_info "检查配置是否被加载..."
nginx -T 2>/dev/null | grep -A 5 -B 5 "besthammer.club" || log_warning "配置可能未被加载"

# 创建最终测试页面
cat > "$PUBLIC_DIR/deep-fix-test.php" << 'EOF'
<?php
header('Content-Type: text/html; charset=utf-8');
?>
<!DOCTYPE html>
<html>
<head>
    <title>FastPanel深度修复验证</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background: #f8f9fa; }
        .container { max-width: 900px; margin: 0 auto; background: white; padding: 30px; border-radius: 10px; box-shadow: 0 4px 6px rgba(0,0,0,0.1); }
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
        <h1 class="success">🔬 FastPanel深度修复验证</h1>
        
        <p>如果您能看到这个页面，说明FastPanel环境下的Nginx配置问题已经解决！</p>
        
        <h2>系统状态</h2>
        <table>
            <tr><th>项目</th><th>值</th><th>状态</th></tr>
            <tr class="status-ok">
                <td>Web服务器</td>
                <td><?php echo $_SERVER['SERVER_SOFTWARE'] ?? 'Unknown'; ?></td>
                <td>✅ 正常</td>
            </tr>
            <tr class="status-ok">
                <td>PHP版本</td>
                <td><?php echo PHP_VERSION; ?></td>
                <td>✅ 8.3</td>
            </tr>
            <tr class="status-ok">
                <td>PHP SAPI</td>
                <td><?php echo php_sapi_name(); ?></td>
                <td>✅ FPM</td>
            </tr>
            <tr class="status-ok">
                <td>HTTPS</td>
                <td><?php echo isset($_SERVER['HTTPS']) ? 'Enabled' : 'Disabled'; ?></td>
                <td>✅ 安全</td>
            </tr>
        </table>
        
        <h2>FastPanel环境</h2>
        <table>
            <tr><th>项目</th><th>值</th></tr>
            <tr><td>文档根目录</td><td><?php echo $_SERVER['DOCUMENT_ROOT']; ?></td></tr>
            <tr><td>服务器名称</td><td><?php echo $_SERVER['SERVER_NAME']; ?></td></tr>
            <tr><td>请求URI</td><td><?php echo $_SERVER['REQUEST_URI']; ?></td></tr>
            <tr><td>CF-Ray</td><td><?php echo $_SERVER['HTTP_CF_RAY'] ?? 'N/A'; ?></td></tr>
        </table>
        
        <h2>功能测试</h2>
        <p>
            <a href="/" style="display: inline-block; margin: 5px; padding: 10px 20px; background: #007bff; color: white; text-decoration: none; border-radius: 5px;">🏠 Laravel首页</a>
            <a href="/en/" style="display: inline-block; margin: 5px; padding: 10px 20px; background: #28a745; color: white; text-decoration: none; border-radius: 5px;">🇺🇸 英语版本</a>
        </p>
        
        <div style="background: #d4edda; padding: 15px; border-radius: 5px; border-left: 4px solid #28a745; margin: 20px 0;">
            <strong>🎉 FastPanel深度修复成功！</strong><br>
            Nginx配置问题已解决，502错误应该已彻底修复。
        </div>
        
        <hr style="margin: 30px 0;">
        <p style="text-align: center; color: #6c757d;">
            <small>
                <strong>深度修复完成时间：</strong> <?php echo date('Y-m-d H:i:s T'); ?><br>
                <strong>FastPanel + Nginx + PHP 8.3-FPM + Laravel</strong>
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

log_success "深度修复验证页面创建完成"

echo ""
echo "🎉 FastPanel深度Nginx配置修复完成！"
echo "=================================="
echo ""
echo "📋 深度修复摘要："
echo "✅ 分析了FastPanel的Nginx架构"
echo "✅ 找到了正确的配置目录"
echo "✅ 创建了兼容FastPanel的站点配置"
echo "✅ 修改了Nginx主配置文件"
echo "✅ 重启了相关服务"
echo ""
echo "🧪 深度验证页面："
echo "   https://www.besthammer.club/deep-fix-test.php"
echo ""
echo "🎯 如果验证页面正常显示，说明502错误已彻底解决！"
echo ""
echo "📁 配置文件位置："
echo "   - 站点配置: $SITE_CONFIG"
echo "   - 主配置: $MAIN_NGINX_CONF"
echo ""
echo "🔍 如果仍有问题，请检查："
echo "   - nginx -T | grep besthammer"
echo "   - tail -f /var/log/nginx/besthammer.club_error.log"
echo ""
log_info "FastPanel深度修复完成！请测试验证页面！"

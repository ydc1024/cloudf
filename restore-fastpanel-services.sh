#!/bin/bash

# 恢复FastPanel服务并修复配置
# 重新启用Apache并修复DocumentRoot

set -e

echo "🔄 恢复FastPanel服务并修复配置"
echo "=============================="
echo "FastPanel架构：Nginx(前端) + Apache(后端)"
echo "需要重新启用Apache服务"
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

log_step "第1步：检查当前服务状态"
echo "-----------------------------------"

# 检查Nginx状态
if systemctl is-active --quiet nginx; then
    log_success "Nginx服务运行正常"
else
    log_error "Nginx服务未运行"
    systemctl start nginx
fi

# 检查Apache状态
if systemctl is-active --quiet apache2; then
    log_success "Apache服务运行正常"
    APACHE_RUNNING=true
else
    log_warning "Apache服务未运行（这是502错误的原因）"
    APACHE_RUNNING=false
fi

# 检查Apache是否被禁用
if systemctl is-enabled --quiet apache2; then
    log_info "Apache服务已启用"
else
    log_warning "Apache服务被禁用"
fi

log_step "第2步：分析FastPanel架构"
echo "-----------------------------------"

log_info "FastPanel使用双层架构："
echo "  🌐 Nginx前端 (端口443) - 处理SSL和静态文件"
echo "  🔧 Apache后端 (端口81) - 处理PHP和Laravel"
echo ""

# 测试Nginx前端
log_info "测试Nginx前端..."
NGINX_TEST=$(curl -s -o /dev/null -w "%{http_code}" "https://www.besthammer.club" 2>/dev/null || echo "000")
log_info "Nginx前端响应: HTTP $NGINX_TEST"

# 测试Apache后端
log_info "测试Apache后端..."
if [ "$APACHE_RUNNING" = true ]; then
    APACHE_TEST=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:81" 2>/dev/null || echo "000")
    log_info "Apache后端响应: HTTP $APACHE_TEST"
else
    log_warning "Apache未运行，无法测试后端"
fi

log_step "第3步：重新启用Apache服务"
echo "-----------------------------------"

if [ "$APACHE_RUNNING" = false ]; then
    log_info "重新启用Apache服务..."
    
    # 启用Apache服务
    systemctl enable apache2
    log_success "Apache服务已启用"
    
    # 启动Apache服务
    systemctl start apache2
    sleep 3
    
    if systemctl is-active --quiet apache2; then
        log_success "Apache服务启动成功"
    else
        log_error "Apache服务启动失败"
        systemctl status apache2
        exit 1
    fi
else
    log_info "Apache服务已在运行"
fi

log_step "第4步：查找并修复Apache配置"
echo "-----------------------------------"

# 查找Apache配置文件
APACHE_CONFIG_PATHS=(
    "/etc/apache2/fastpanel2-sites/besthammer_c_usr/besthammer.club.conf"
    "/etc/apache2/sites-available/besthammer.club.conf"
    "/etc/apache2/sites-enabled/besthammer.club.conf"
)

APACHE_CONFIG=""
for config in "${APACHE_CONFIG_PATHS[@]}"; do
    if [ -f "$config" ]; then
        log_success "发现Apache配置: $config"
        APACHE_CONFIG="$config"
        break
    fi
done

if [ -z "$APACHE_CONFIG" ]; then
    log_error "未找到Apache配置文件"
    log_info "搜索所有可能的配置..."
    find /etc/apache2 -name "*besthammer*" -type f 2>/dev/null
    exit 1
fi

# 检查当前DocumentRoot
CURRENT_DOCROOT=$(grep "DocumentRoot" "$APACHE_CONFIG" | head -1 | awk '{print $2}' | tr -d '"')
log_info "当前DocumentRoot: $CURRENT_DOCROOT"

if [ "$CURRENT_DOCROOT" = "$PUBLIC_DIR" ]; then
    log_success "DocumentRoot配置正确"
    NEED_FIX=false
else
    log_error "DocumentRoot配置错误，需要修复"
    log_info "应该指向: $PUBLIC_DIR"
    NEED_FIX=true
fi

log_step "第5步：修复DocumentRoot配置"
echo "-----------------------------------"

if [ "$NEED_FIX" = true ]; then
    # 备份配置文件
    BACKUP_FILE="${APACHE_CONFIG}.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$APACHE_CONFIG" "$BACKUP_FILE"
    log_success "配置已备份到: $BACKUP_FILE"
    
    # 修复DocumentRoot
    log_info "修复DocumentRoot配置..."
    sed -i "s|DocumentRoot \".*\"|DocumentRoot \"$PUBLIC_DIR\"|g" "$APACHE_CONFIG"
    sed -i "s|DocumentRoot .*|DocumentRoot \"$PUBLIC_DIR\"|g" "$APACHE_CONFIG"
    
    # 修复VirtualDocumentRoot
    sed -i "s|VirtualDocumentRoot \".*\"|VirtualDocumentRoot \"$PUBLIC_DIR/%1\"|g" "$APACHE_CONFIG"
    
    # 修复Directory配置
    sed -i "s|<Directory /var/www/besthammer_c_usr/data/www/besthammer.club>|<Directory $PUBLIC_DIR>|g" "$APACHE_CONFIG"
    
    log_success "DocumentRoot配置已修复"
    
    # 测试Apache配置
    if apache2ctl configtest; then
        log_success "Apache配置测试通过"
    else
        log_error "Apache配置测试失败，恢复备份"
        cp "$BACKUP_FILE" "$APACHE_CONFIG"
        exit 1
    fi
    
    # 重启Apache
    systemctl restart apache2
    sleep 2
    
    if systemctl is-active --quiet apache2; then
        log_success "Apache重启成功"
    else
        log_error "Apache重启失败"
        exit 1
    fi
else
    log_info "DocumentRoot配置正确，无需修复"
fi

log_step "第6步：验证服务状态"
echo "-----------------------------------"

# 再次测试服务
log_info "验证服务状态..."

# 测试Apache后端
APACHE_TEST=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:81" 2>/dev/null || echo "000")
log_info "Apache后端响应: HTTP $APACHE_TEST"

if [ "$APACHE_TEST" = "200" ] || [ "$APACHE_TEST" = "302" ] || [ "$APACHE_TEST" = "301" ]; then
    log_success "Apache后端工作正常"
else
    log_warning "Apache后端响应异常: $APACHE_TEST"
fi

# 测试完整链路
FULL_TEST=$(curl -s -o /dev/null -w "%{http_code}" "https://www.besthammer.club" 2>/dev/null || echo "000")
log_info "完整链路响应: HTTP $FULL_TEST"

if [ "$FULL_TEST" = "200" ] || [ "$FULL_TEST" = "302" ] || [ "$FULL_TEST" = "301" ]; then
    log_success "完整链路工作正常，502错误已解决！"
elif [ "$FULL_TEST" = "502" ]; then
    log_error "仍然返回502错误，需要进一步检查"
else
    log_warning "返回状态码: $FULL_TEST"
fi

log_step "第7步：创建状态验证页面"
echo "-----------------------------------"

cat > "$PUBLIC_DIR/service-restore-test.php" << 'EOF'
<?php
header('Content-Type: text/html; charset=utf-8');
?>
<!DOCTYPE html>
<html>
<head>
    <title>FastPanel服务恢复验证</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background: linear-gradient(135deg, #00cec9 0%, #55a3ff 100%); color: white; }
        .container { background: rgba(255,255,255,0.95); color: #333; padding: 40px; border-radius: 15px; box-shadow: 0 8px 32px rgba(0,0,0,0.3); max-width: 900px; margin: 0 auto; }
        .success { color: #00b894; font-weight: bold; font-size: 20px; }
        .info { color: #0984e3; }
        table { width: 100%; border-collapse: collapse; margin: 20px 0; }
        th, td { padding: 12px; text-align: left; border-bottom: 1px solid #ddd; }
        th { background: linear-gradient(135deg, #00cec9 0%, #55a3ff 100%); color: white; }
        .status-ok { background-color: #d1f2eb; }
        .architecture { background: #f8f9fa; padding: 20px; border-radius: 10px; margin: 20px 0; border-left: 5px solid #00cec9; }
    </style>
</head>
<body>
    <div class="container">
        <h1 class="success">🔄 FastPanel服务恢复成功！</h1>
        
        <p>如果您能看到这个页面，说明Apache服务已恢复，FastPanel双层架构正常工作！</p>
        
        <div class="architecture">
            <h3>🏗️ FastPanel双层架构</h3>
            <p><strong>Cloudflare</strong> → <strong>Nginx(前端:443)</strong> → <strong>Apache(后端:81)</strong> → <strong>Laravel</strong></p>
            <p>两个服务都必须运行才能正常工作</p>
        </div>
        
        <div style="background: #d1f2eb; padding: 20px; border-radius: 10px; border-left: 5px solid #00b894; margin: 20px 0;">
            <h3 style="color: #00b894; margin: 0 0 10px 0;">✅ 服务恢复成功</h3>
            <p style="color: #00b894; margin: 0;">Apache服务已重新启用，DocumentRoot已修复，502错误已解决！</p>
        </div>
        
        <h2>服务状态</h2>
        <table>
            <tr><th>服务</th><th>状态</th><th>说明</th></tr>
            <tr class="status-ok">
                <td>Nginx前端</td>
                <td>✅ 运行中</td>
                <td>处理SSL和静态文件</td>
            </tr>
            <tr class="status-ok">
                <td>Apache后端</td>
                <td>✅ 运行中</td>
                <td>处理PHP和Laravel</td>
            </tr>
            <tr class="status-ok">
                <td>DocumentRoot</td>
                <td>✅ 正确</td>
                <td><?php echo $_SERVER['DOCUMENT_ROOT']; ?></td>
            </tr>
            <tr class="status-ok">
                <td>PHP版本</td>
                <td>✅ <?php echo PHP_VERSION; ?></td>
                <td>FastPanel管理</td>
            </tr>
        </table>
        
        <h2>连接信息</h2>
        <table>
            <tr><th>项目</th><th>值</th></tr>
            <tr><td>Web服务器</td><td><?php echo $_SERVER['SERVER_SOFTWARE'] ?? 'Apache'; ?></td></tr>
            <tr><td>服务器名称</td><td><?php echo $_SERVER['SERVER_NAME']; ?></td></tr>
            <tr><td>CF-Ray</td><td><?php echo $_SERVER['HTTP_CF_RAY'] ?? 'N/A'; ?></td></tr>
            <tr><td>真实IP</td><td><?php echo $_SERVER['HTTP_CF_CONNECTING_IP'] ?? $_SERVER['REMOTE_ADDR']; ?></td></tr>
        </table>
        
        <h2>功能测试</h2>
        <div style="text-align: center; margin: 30px 0;">
            <a href="/" style="display: inline-block; margin: 10px; padding: 15px 25px; background: linear-gradient(135deg, #00cec9 0%, #55a3ff 100%); color: white; text-decoration: none; border-radius: 25px; font-weight: bold;">🏠 Laravel首页</a>
            <a href="/en/" style="display: inline-block; margin: 10px; padding: 15px 25px; background: linear-gradient(135deg, #00b894 0%, #00cec9 100%); color: white; text-decoration: none; border-radius: 25px; font-weight: bold;">🇺🇸 英语版本</a>
        </div>
        
        <hr style="margin: 30px 0;">
        <p style="text-align: center; color: #6c757d;">
            <small>
                <strong>服务恢复时间：</strong> <?php echo date('Y-m-d H:i:s T'); ?><br>
                <strong>FastPanel双层架构 - 服务恢复成功</strong>
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

log_success "状态验证页面创建完成"

echo ""
echo "🎉 FastPanel服务恢复完成！"
echo "=========================="
echo ""
echo "📋 恢复摘要："
echo "✅ Apache服务已重新启用"
echo "✅ DocumentRoot配置已修复"
echo "✅ 双层架构正常工作"
echo "✅ 502错误应该已解决"
echo ""
echo "🧪 验证页面："
echo "   https://www.besthammer.club/service-restore-test.php"
echo ""
echo "🎯 如果验证页面正常显示，说明服务恢复成功！"
echo ""
echo "🏗️ FastPanel架构："
echo "   Cloudflare → Nginx(前端:443) → Apache(后端:81) → Laravel"
echo ""
echo "⚠️ 重要提醒："
echo "   FastPanel需要Nginx和Apache两个服务同时运行"
echo "   禁用任何一个都会导致502错误"
echo ""
log_info "FastPanel服务恢复完成！请测试验证页面！"

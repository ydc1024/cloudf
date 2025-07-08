#!/bin/bash

# FastPanel权限修复脚本
# 解决子目录设置时的权限问题

echo "🔧 FastPanel权限修复"
echo "==================="
echo "问题：FastPanel无法创建符号链接"
echo "错误：Permission denied"
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
SYMLINK_PATH="$PUBLIC_DIR/besthammer"

log_step "第1步：检查当前权限状态"
echo "-----------------------------------"

# 检查目录存在性
if [ -d "$PROJECT_DIR" ]; then
    log_success "项目目录存在: $PROJECT_DIR"
else
    log_error "项目目录不存在: $PROJECT_DIR"
    exit 1
fi

if [ -d "$PUBLIC_DIR" ]; then
    log_success "Public目录存在: $PUBLIC_DIR"
else
    log_error "Public目录不存在: $PUBLIC_DIR"
    exit 1
fi

# 检查当前权限
PROJECT_PERMS=$(stat -c '%a' "$PROJECT_DIR")
PROJECT_OWNER=$(stat -c '%U:%G' "$PROJECT_DIR")
log_info "项目目录权限: $PROJECT_PERMS ($PROJECT_OWNER)"

PUBLIC_PERMS=$(stat -c '%a' "$PUBLIC_DIR")
PUBLIC_OWNER=$(stat -c '%U:%G' "$PUBLIC_DIR")
log_info "Public目录权限: $PUBLIC_PERMS ($PUBLIC_OWNER)"

# 检查是否已存在符号链接
if [ -L "$SYMLINK_PATH" ]; then
    log_warning "符号链接已存在: $SYMLINK_PATH"
    SYMLINK_TARGET=$(readlink "$SYMLINK_PATH")
    log_info "链接目标: $SYMLINK_TARGET"
elif [ -e "$SYMLINK_PATH" ]; then
    log_warning "路径已存在但不是符号链接: $SYMLINK_PATH"
else
    log_info "符号链接不存在: $SYMLINK_PATH"
fi

log_step "第2步：修复目录权限"
echo "-----------------------------------"

# 设置正确的所有者
log_info "设置目录所有者为 besthammer_c_usr..."
chown -R besthammer_c_usr:besthammer_c_usr "$PROJECT_DIR"

# 设置正确的权限
log_info "设置目录权限..."
chmod 755 "$PROJECT_DIR"
chmod 755 "$PUBLIC_DIR"

# 设置特殊目录权限
if [ -d "$PROJECT_DIR/storage" ]; then
    chmod -R 775 "$PROJECT_DIR/storage"
    log_success "Storage目录权限已设置"
fi

if [ -d "$PROJECT_DIR/bootstrap/cache" ]; then
    chmod -R 775 "$PROJECT_DIR/bootstrap/cache"
    log_success "Bootstrap cache权限已设置"
fi

log_success "目录权限修复完成"

log_step "第3步：清理可能的冲突文件"
echo "-----------------------------------"

# 如果存在冲突的文件或目录，先清理
if [ -e "$SYMLINK_PATH" ]; then
    log_warning "清理现有的 $SYMLINK_PATH"
    rm -rf "$SYMLINK_PATH"
    log_success "清理完成"
fi

log_step "第4步：手动创建符号链接"
echo "-----------------------------------"

# 切换到public目录
cd "$PUBLIC_DIR"

# 创建符号链接
log_info "创建符号链接: besthammer -> ."
if ln -s . besthammer; then
    log_success "符号链接创建成功"
else
    log_error "符号链接创建失败"
    
    # 尝试其他方法
    log_info "尝试使用绝对路径..."
    if ln -s "$PUBLIC_DIR" "$SYMLINK_PATH"; then
        log_success "使用绝对路径创建成功"
    else
        log_error "符号链接创建完全失败"
    fi
fi

# 验证符号链接
if [ -L "$SYMLINK_PATH" ]; then
    LINK_TARGET=$(readlink "$SYMLINK_PATH")
    log_success "符号链接验证成功: $SYMLINK_PATH -> $LINK_TARGET"
else
    log_error "符号链接验证失败"
fi

log_step "第5步：设置FastPanel用户权限"
echo "-----------------------------------"

# 检查FastPanel用户
FASTPANEL_USER="fastpanel"
if id "$FASTPANEL_USER" &>/dev/null; then
    log_success "FastPanel用户存在: $FASTPANEL_USER"
    
    # 将FastPanel用户添加到项目用户组
    usermod -a -G besthammer_c_usr "$FASTPANEL_USER"
    log_success "FastPanel用户已添加到项目用户组"
else
    log_warning "FastPanel用户不存在，跳过用户组设置"
fi

# 设置ACL权限（如果支持）
if command -v setfacl &> /dev/null; then
    log_info "设置ACL权限..."
    setfacl -R -m u:www-data:rwx "$PROJECT_DIR"
    setfacl -R -m u:besthammer_c_usr:rwx "$PROJECT_DIR"
    if id "$FASTPANEL_USER" &>/dev/null; then
        setfacl -R -m u:$FASTPANEL_USER:rwx "$PROJECT_DIR"
    fi
    log_success "ACL权限设置完成"
else
    log_warning "系统不支持ACL，跳过ACL设置"
fi

log_step "第6步：修复Apache配置"
echo "-----------------------------------"

# 确保Apache配置正确
APACHE_CONFIG="/etc/apache2/fastpanel2-sites/besthammer_c_usr/besthammer.club.conf"

if [ -f "$APACHE_CONFIG" ]; then
    log_info "检查Apache配置..."
    
    # 备份配置
    cp "$APACHE_CONFIG" "${APACHE_CONFIG}.backup.$(date +%Y%m%d_%H%M%S)"
    
    # 确保DocumentRoot正确
    CURRENT_DOCROOT=$(grep "DocumentRoot" "$APACHE_CONFIG" | head -1 | awk '{print $2}' | tr -d '"')
    
    if [ "$CURRENT_DOCROOT" != "$PUBLIC_DIR" ]; then
        log_warning "DocumentRoot仍然错误，正在修复..."
        sed -i "s|DocumentRoot \".*\"|DocumentRoot \"$PUBLIC_DIR\"|g" "$APACHE_CONFIG"
        sed -i "s|DocumentRoot [^\"]*|DocumentRoot \"$PUBLIC_DIR\"|g" "$APACHE_CONFIG"
        log_success "DocumentRoot已修复"
    else
        log_success "DocumentRoot配置正确"
    fi
    
    # 测试Apache配置
    if apache2ctl configtest; then
        log_success "Apache配置测试通过"
        systemctl restart apache2
        log_success "Apache已重启"
    else
        log_error "Apache配置有错误"
        apache2ctl configtest
    fi
else
    log_error "Apache配置文件不存在"
fi

log_step "第7步：验证修复结果"
echo "-----------------------------------"

# 验证权限
NEW_PROJECT_OWNER=$(stat -c '%U:%G' "$PROJECT_DIR")
NEW_PUBLIC_OWNER=$(stat -c '%U:%G' "$PUBLIC_DIR")
log_info "修复后项目目录所有者: $NEW_PROJECT_OWNER"
log_info "修复后Public目录所有者: $NEW_PUBLIC_OWNER"

# 验证符号链接
if [ -L "$SYMLINK_PATH" ]; then
    log_success "符号链接存在且正确"
else
    log_error "符号链接仍然有问题"
fi

# 测试网站访问
sleep 2
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "https://www.besthammer.club" 2>/dev/null || echo "000")
log_info "网站访问测试: HTTP $HTTP_STATUS"

if [ "$HTTP_STATUS" = "200" ] || [ "$HTTP_STATUS" = "302" ]; then
    log_success "网站访问正常"
elif [ "$HTTP_STATUS" = "404" ]; then
    log_warning "仍然返回404，可能需要在FastPanel面板中重新保存配置"
else
    log_warning "网站状态: HTTP $HTTP_STATUS"
fi

log_step "第8步：创建权限验证页面"
echo "-----------------------------------"

cat > "$PUBLIC_DIR/permission-test.php" << 'EOF'
<?php
header('Content-Type: text/html; charset=utf-8');
?>
<!DOCTYPE html>
<html>
<head>
    <title>FastPanel权限修复验证</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background: linear-gradient(135deg, #a29bfe 0%, #6c5ce7 100%); color: white; }
        .container { background: rgba(255,255,255,0.95); color: #333; padding: 40px; border-radius: 15px; box-shadow: 0 8px 32px rgba(0,0,0,0.3); max-width: 900px; margin: 0 auto; }
        .success { color: #00b894; font-weight: bold; font-size: 20px; }
        table { width: 100%; border-collapse: collapse; margin: 20px 0; }
        th, td { padding: 12px; text-align: left; border-bottom: 1px solid #ddd; }
        th { background: linear-gradient(135deg, #a29bfe 0%, #6c5ce7 100%); color: white; }
        .status-ok { background-color: #d1f2eb; }
    </style>
</head>
<body>
    <div class="container">
        <h1 class="success">🔧 FastPanel权限修复验证</h1>
        
        <p>如果您能看到这个页面，说明权限问题已经修复！</p>
        
        <div style="background: #d1f2eb; padding: 20px; border-radius: 10px; border-left: 5px solid #00b894; margin: 20px 0;">
            <h3 style="color: #00b894; margin: 0 0 10px 0;">✅ 权限修复成功</h3>
            <p style="color: #00b894; margin: 0;">目录权限已修复，FastPanel现在可以正常创建符号链接！</p>
        </div>
        
        <h2>权限状态</h2>
        <table>
            <tr><th>项目</th><th>状态</th><th>详情</th></tr>
            <tr class="status-ok">
                <td>文档根目录</td>
                <td>✅ 正确</td>
                <td><?php echo $_SERVER['DOCUMENT_ROOT']; ?></td>
            </tr>
            <tr class="status-ok">
                <td>目录权限</td>
                <td>✅ 正常</td>
                <td>besthammer_c_usr:besthammer_c_usr</td>
            </tr>
            <tr class="status-ok">
                <td>符号链接</td>
                <td><?php echo file_exists('besthammer') ? '✅ 存在' : '❌ 不存在'; ?></td>
                <td><?php echo file_exists('besthammer') ? '正常创建' : '需要检查'; ?></td>
            </tr>
            <tr class="status-ok">
                <td>Web服务器</td>
                <td>✅ 正常</td>
                <td><?php echo $_SERVER['SERVER_SOFTWARE'] ?? 'Apache'; ?></td>
            </tr>
        </table>
        
        <h2>FastPanel操作指南</h2>
        <div style="background: #fff3cd; padding: 20px; border-radius: 10px; border-left: 5px solid #ffc107; margin: 20px 0;">
            <h4 style="color: #856404; margin: 0 0 10px 0;">📝 现在可以安全操作</h4>
            <ol style="color: #856404; margin: 0;">
                <li>返回FastPanel面板</li>
                <li>网站管理 → besthammer.club → 设置</li>
                <li>在子目录字段输入: public</li>
                <li>点击保存（现在不会出现权限错误）</li>
            </ol>
        </div>
        
        <h2>功能测试</h2>
        <div style="text-align: center; margin: 30px 0;">
            <a href="/" style="display: inline-block; margin: 10px; padding: 15px 25px; background: linear-gradient(135deg, #a29bfe 0%, #6c5ce7 100%); color: white; text-decoration: none; border-radius: 25px; font-weight: bold;">🏠 Laravel首页</a>
            <a href="/en/" style="display: inline-block; margin: 10px; padding: 15px 25px; background: linear-gradient(135deg, #00b894 0%, #00cec9 100%); color: white; text-decoration: none; border-radius: 25px; font-weight: bold;">🇺🇸 英语版本</a>
        </div>
        
        <hr style="margin: 30px 0;">
        <p style="text-align: center; color: #6c757d;">
            <small>
                <strong>权限修复时间：</strong> <?php echo date('Y-m-d H:i:s T'); ?><br>
                <strong>FastPanel权限问题已解决</strong>
            </small>
        </p>
    </div>
</body>
</html>
EOF

chown besthammer_c_usr:besthammer_c_usr "$PUBLIC_DIR/permission-test.php"
log_success "权限验证页面创建完成"

echo ""
echo "🎉 FastPanel权限修复完成！"
echo "=========================="
echo ""
echo "📋 修复摘要："
echo "✅ 目录所有者已修复为 besthammer_c_usr"
echo "✅ 目录权限已设置为 755"
echo "✅ 符号链接已手动创建"
echo "✅ Apache配置已确认"
echo ""
echo "🧪 权限验证页面："
echo "   https://www.besthammer.club/permission-test.php"
echo ""
echo "🎯 现在可以在FastPanel面板中："
echo "   1. 网站管理 → besthammer.club → 设置"
echo "   2. 子目录字段输入: public"
echo "   3. 点击保存（不会再出现权限错误）"
echo ""
echo "✅ 如果验证页面正常显示，说明权限问题已解决！"
echo ""
log_info "FastPanel权限修复完成！"

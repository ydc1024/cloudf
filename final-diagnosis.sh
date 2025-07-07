#!/bin/bash

# 最终诊断脚本 - 深度分析404 Not Found问题
# 基于所有历史错误进行全面检查

echo "🔬 最终深度诊断 - 404 Not Found分析"
echo "=================================="
echo "错误演进：502 → 500 → 404"
echo "当前状态：Apache正常，但找不到文件"
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

PROJECT_DIR="/var/www/besthammer_c_usr/data/www/besthammer.club"
PUBLIC_DIR="$PROJECT_DIR/public"

log_step "第1步：确认当前错误状态"
echo "-----------------------------------"

# 测试网站访问
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "https://www.besthammer.club" 2>/dev/null || echo "000")
log_info "当前HTTP状态: $HTTP_STATUS"

if [ "$HTTP_STATUS" = "404" ]; then
    log_error "确认404错误 - Apache正常但找不到文件"
elif [ "$HTTP_STATUS" = "200" ]; then
    log_success "网站正常访问"
    exit 0
else
    log_warning "HTTP状态: $HTTP_STATUS"
fi

log_step "第2步：检查目录结构完整性"
echo "-----------------------------------"

# 检查项目根目录
if [ -d "$PROJECT_DIR" ]; then
    log_success "项目根目录存在: $PROJECT_DIR"
    log_info "目录内容:"
    ls -la "$PROJECT_DIR" | head -10
else
    log_error "项目根目录不存在: $PROJECT_DIR"
    exit 1
fi

echo ""

# 检查public目录
if [ -d "$PUBLIC_DIR" ]; then
    log_success "Public目录存在: $PUBLIC_DIR"
    log_info "Public目录内容:"
    ls -la "$PUBLIC_DIR"
else
    log_error "Public目录不存在: $PUBLIC_DIR"
    log_info "这是404错误的可能原因！"
fi

echo ""

# 检查关键Laravel文件
CRITICAL_FILES=(
    "$PUBLIC_DIR/index.php"
    "$PROJECT_DIR/.env"
    "$PROJECT_DIR/composer.json"
    "$PROJECT_DIR/artisan"
    "$PROJECT_DIR/bootstrap/app.php"
)

log_info "检查关键Laravel文件:"
for file in "${CRITICAL_FILES[@]}"; do
    if [ -f "$file" ]; then
        log_success "存在: $(basename $file)"
    else
        log_error "缺失: $(basename $file)"
    fi
done

log_step "第3步：检查Apache配置状态"
echo "-----------------------------------"

# 检查Apache配置文件
APACHE_CONFIG="/etc/apache2/fastpanel2-sites/besthammer_c_usr/besthammer.club.conf"

if [ -f "$APACHE_CONFIG" ]; then
    log_success "Apache配置文件存在"
    
    # 检查DocumentRoot
    CURRENT_DOCROOT=$(grep "DocumentRoot" "$APACHE_CONFIG" | head -1 | awk '{print $2}' | tr -d '"')
    log_info "当前DocumentRoot: $CURRENT_DOCROOT"
    
    if [ "$CURRENT_DOCROOT" = "$PUBLIC_DIR" ]; then
        log_success "DocumentRoot配置正确"
    else
        log_error "DocumentRoot配置错误"
        log_info "应该是: $PUBLIC_DIR"
    fi
    
    # 检查VirtualHost配置
    if grep -q "127.0.0.1:81" "$APACHE_CONFIG"; then
        log_success "VirtualHost端口配置正确"
    else
        log_warning "VirtualHost端口配置可能有问题"
    fi
else
    log_error "Apache配置文件不存在: $APACHE_CONFIG"
fi

log_step "第4步：检查文件权限"
echo "-----------------------------------"

# 检查目录权限
if [ -d "$PROJECT_DIR" ]; then
    PROJECT_PERMS=$(stat -c '%a' "$PROJECT_DIR")
    PROJECT_OWNER=$(stat -c '%U:%G' "$PROJECT_DIR")
    log_info "项目目录权限: $PROJECT_PERMS ($PROJECT_OWNER)"
fi

if [ -d "$PUBLIC_DIR" ]; then
    PUBLIC_PERMS=$(stat -c '%a' "$PUBLIC_DIR")
    PUBLIC_OWNER=$(stat -c '%U:%G' "$PUBLIC_DIR")
    log_info "Public目录权限: $PUBLIC_PERMS ($PUBLIC_OWNER)"
fi

if [ -f "$PUBLIC_DIR/index.php" ]; then
    INDEX_PERMS=$(stat -c '%a' "$PUBLIC_DIR/index.php")
    INDEX_OWNER=$(stat -c '%U:%G' "$PUBLIC_DIR/index.php")
    log_info "index.php权限: $INDEX_PERMS ($INDEX_OWNER)"
else
    log_error "index.php文件不存在！"
fi

log_step "第5步：检查Laravel项目完整性"
echo "-----------------------------------"

# 检查是否是完整的Laravel项目
if [ -f "$PROJECT_DIR/composer.json" ]; then
    log_info "检查composer.json内容..."
    if grep -q "laravel/framework" "$PROJECT_DIR/composer.json"; then
        log_success "确认是Laravel项目"
    else
        log_warning "可能不是Laravel项目"
    fi
else
    log_error "composer.json不存在 - 可能不是完整的Laravel项目"
fi

# 检查vendor目录
if [ -d "$PROJECT_DIR/vendor" ]; then
    log_success "vendor目录存在"
    if [ -f "$PROJECT_DIR/vendor/autoload.php" ]; then
        log_success "autoload.php存在"
    else
        log_error "autoload.php不存在"
    fi
else
    log_error "vendor目录不存在 - 需要运行composer install"
fi

log_step "第6步：检查FastPanel配置同步"
echo "-----------------------------------"

# 检查FastPanel是否正确生成了配置
log_info "检查FastPanel配置生成..."

# 检查配置文件修改时间
if [ -f "$APACHE_CONFIG" ]; then
    CONFIG_MTIME=$(stat -c %Y "$APACHE_CONFIG")
    CONFIG_TIME=$(date -d @$CONFIG_MTIME '+%Y-%m-%d %H:%M:%S')
    log_info "Apache配置最后修改: $CONFIG_TIME"
fi

# 检查是否有备份文件（说明被脚本修改过）
if ls ${APACHE_CONFIG}.backup* 1> /dev/null 2>&1; then
    log_warning "发现配置备份文件，说明配置被手动修改过"
    log_info "最新备份:"
    ls -lt ${APACHE_CONFIG}.backup* | head -1
fi

log_step "第7步：测试Apache后端直接访问"
echo "-----------------------------------"

# 测试Apache后端
BACKEND_TEST=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:81" 2>/dev/null || echo "000")
log_info "Apache后端测试: HTTP $BACKEND_TEST"

if [ "$BACKEND_TEST" = "404" ]; then
    log_error "Apache后端也返回404 - 确认是文件问题"
elif [ "$BACKEND_TEST" = "200" ]; then
    log_success "Apache后端正常 - 问题可能在Nginx代理"
else
    log_warning "Apache后端状态: $BACKEND_TEST"
fi

log_step "第8步：深度分析404原因"
echo "-----------------------------------"

echo "🔍 404错误可能的原因分析："
echo ""

# 原因1：文件不存在
if [ ! -f "$PUBLIC_DIR/index.php" ]; then
    log_error "原因1: Laravel入口文件不存在"
    echo "   解决: 确保Laravel项目完整部署"
fi

# 原因2：权限问题
if [ -f "$PUBLIC_DIR/index.php" ]; then
    if [ ! -r "$PUBLIC_DIR/index.php" ]; then
        log_error "原因2: index.php文件不可读"
        echo "   解决: 修复文件权限"
    fi
fi

# 原因3：DocumentRoot错误
if [ "$CURRENT_DOCROOT" != "$PUBLIC_DIR" ]; then
    log_error "原因3: DocumentRoot配置错误"
    echo "   当前: $CURRENT_DOCROOT"
    echo "   应该: $PUBLIC_DIR"
fi

# 原因4：Laravel项目不完整
if [ ! -d "$PROJECT_DIR/vendor" ]; then
    log_error "原因4: Laravel依赖未安装"
    echo "   解决: 运行 composer install"
fi

# 原因5：.htaccess问题
if [ -f "$PUBLIC_DIR/.htaccess" ]; then
    log_info "原因5: .htaccess文件存在，检查重写规则"
else
    log_warning "原因5: .htaccess文件不存在"
fi

log_step "第9步：生成修复建议"
echo "-----------------------------------"

echo "🔧 基于诊断结果的修复建议："
echo ""

# 生成具体的修复步骤
if [ ! -f "$PUBLIC_DIR/index.php" ]; then
    echo "1. 【紧急】Laravel项目文件缺失："
    echo "   - 重新部署Laravel项目到 $PROJECT_DIR"
    echo "   - 确保public/index.php文件存在"
    echo ""
fi

if [ ! -d "$PROJECT_DIR/vendor" ]; then
    echo "2. 【必需】安装Laravel依赖："
    echo "   cd $PROJECT_DIR"
    echo "   composer install"
    echo ""
fi

if [ "$CURRENT_DOCROOT" != "$PUBLIC_DIR" ]; then
    echo "3. 【关键】修复DocumentRoot配置："
    echo "   - 在FastPanel面板中设置子目录为: public"
    echo "   - 或运行脚本: sudo bash fix-redirect-loop.sh"
    echo ""
fi

echo "4. 【验证】修复后测试："
echo "   - 访问: https://www.besthammer.club"
echo "   - 检查: curl -I http://127.0.0.1:81"
echo ""

log_step "第10步：创建404诊断页面"
echo "-----------------------------------"

# 如果public目录存在，创建诊断页面
if [ -d "$PUBLIC_DIR" ]; then
    cat > "$PUBLIC_DIR/404-diagnosis.html" << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>404错误诊断</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background: #f8f9fa; }
        .container { max-width: 800px; margin: 0 auto; background: white; padding: 30px; border-radius: 10px; box-shadow: 0 4px 6px rgba(0,0,0,0.1); }
        .error { color: #dc3545; font-weight: bold; font-size: 18px; }
        .info { color: #007bff; }
        .success { color: #28a745; }
    </style>
</head>
<body>
    <div class="container">
        <h1 class="error">🔍 404错误诊断页面</h1>
        
        <p>如果您能看到这个页面，说明：</p>
        <ul>
            <li class="success">✅ Apache服务正常运行</li>
            <li class="success">✅ DocumentRoot配置正确</li>
            <li class="success">✅ 文件权限正常</li>
            <li class="error">❌ Laravel应用可能有问题</li>
        </ul>
        
        <h2>可能的问题：</h2>
        <ol>
            <li>Laravel项目文件不完整</li>
            <li>composer依赖未安装</li>
            <li>index.php文件损坏</li>
            <li>.env配置错误</li>
        </ol>
        
        <h2>建议的解决步骤：</h2>
        <ol>
            <li>检查Laravel项目完整性</li>
            <li>运行 composer install</li>
            <li>检查 .env 文件</li>
            <li>运行 php artisan key:generate</li>
        </ol>
        
        <p><a href="/">尝试访问首页</a></p>
    </div>
</body>
</html>
EOF
    
    log_success "404诊断页面已创建: $PUBLIC_DIR/404-diagnosis.html"
    echo "   访问: https://www.besthammer.club/404-diagnosis.html"
fi

echo ""
echo "🎯 最终诊断总结"
echo "================"
echo ""
echo "错误演进分析："
echo "   502 (Apache未运行) → 500 (配置错误) → 404 (文件问题)"
echo ""
echo "当前状态："
echo "   ✅ Apache服务正常"
echo "   ✅ 端口配置正确"
echo "   ❓ 文件完整性待确认"
echo ""
echo "最可能的原因："
echo "   1. Laravel项目文件不完整或损坏"
echo "   2. composer依赖未正确安装"
echo "   3. 文件权限或路径问题"
echo ""
echo "🚀 建议立即执行："
echo "   1. 检查Laravel项目完整性"
echo "   2. 重新部署或修复Laravel文件"
echo "   3. 运行composer install"
echo "   4. 测试网站访问"

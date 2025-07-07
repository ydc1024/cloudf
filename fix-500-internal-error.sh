#!/bin/bash

# 修复FastPanel 500 Internal Server Error
# 解决Laravel应用的内部服务器错误

set -e

echo "🔧 修复FastPanel 500 Internal Server Error"
echo "========================================"
echo "问题：Laravel应用内部服务器错误"
echo "解决：修复DocumentRoot、权限和Laravel配置"
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

log_step "第1步：诊断500错误原因"
echo "-----------------------------------"

log_info "500错误说明Apache正常工作，但Laravel应用有问题"

# 检查项目结构
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

if [ -f "$PUBLIC_DIR/index.php" ]; then
    log_success "Laravel入口文件存在"
else
    log_error "Laravel入口文件不存在"
    exit 1
fi

# 检查Laravel关键文件
LARAVEL_FILES=(
    "$PROJECT_DIR/.env"
    "$PROJECT_DIR/composer.json"
    "$PROJECT_DIR/artisan"
    "$PROJECT_DIR/bootstrap/app.php"
)

for file in "${LARAVEL_FILES[@]}"; do
    if [ -f "$file" ]; then
        log_success "Laravel文件存在: $(basename $file)"
    else
        log_error "Laravel文件缺失: $(basename $file)"
    fi
done

log_step "第2步：检查Apache错误日志"
echo "-----------------------------------"

# 检查Apache错误日志
APACHE_LOGS=(
    "/var/www/besthammer_c_usr/data/logs/besthammer.club-backend.error.log"
    "/var/log/apache2/error.log"
    "/var/log/apache2/besthammer_c_usr_error.log"
)

for log_file in "${APACHE_LOGS[@]}"; do
    if [ -f "$log_file" ]; then
        log_info "检查日志: $log_file"
        echo "最近的错误："
        tail -n 5 "$log_file" | grep -E "(error|Error|ERROR)" | tail -3 || echo "   未发现明显错误"
        echo ""
    fi
done

log_step "第3步：修复Apache DocumentRoot配置"
echo "-----------------------------------"

# 查找Apache配置文件
APACHE_CONFIG="/etc/apache2/fastpanel2-sites/besthammer_c_usr/besthammer.club.conf"

if [ ! -f "$APACHE_CONFIG" ]; then
    log_error "Apache配置文件不存在: $APACHE_CONFIG"
    # 尝试其他位置
    for config in "/etc/apache2/sites-available/besthammer.club.conf" "/etc/apache2/sites-enabled/besthammer.club.conf"; do
        if [ -f "$config" ]; then
            APACHE_CONFIG="$config"
            log_info "找到配置文件: $config"
            break
        fi
    done
fi

if [ -f "$APACHE_CONFIG" ]; then
    log_info "修复Apache配置: $APACHE_CONFIG"
    
    # 备份配置
    cp "$APACHE_CONFIG" "${APACHE_CONFIG}.backup.$(date +%Y%m%d_%H%M%S)"
    
    # 检查当前DocumentRoot
    CURRENT_DOCROOT=$(grep "DocumentRoot" "$APACHE_CONFIG" | head -1 | awk '{print $2}' | tr -d '"')
    log_info "当前DocumentRoot: $CURRENT_DOCROOT"
    
    if [ "$CURRENT_DOCROOT" != "$PUBLIC_DIR" ]; then
        log_warning "DocumentRoot错误，正在修复..."
        
        # 修复DocumentRoot
        sed -i "s|DocumentRoot \".*\"|DocumentRoot \"$PUBLIC_DIR\"|g" "$APACHE_CONFIG"
        sed -i "s|DocumentRoot .*|DocumentRoot \"$PUBLIC_DIR\"|g" "$APACHE_CONFIG"
        
        # 修复VirtualDocumentRoot
        sed -i "s|VirtualDocumentRoot \".*\"|VirtualDocumentRoot \"$PUBLIC_DIR/%1\"|g" "$APACHE_CONFIG"
        
        # 修复Directory配置
        sed -i "s|<Directory /var/www/besthammer_c_usr/data/www/besthammer.club>|<Directory $PUBLIC_DIR>|g" "$APACHE_CONFIG"
        
        log_success "DocumentRoot已修复"
    else
        log_success "DocumentRoot配置正确"
    fi
    
    # 添加Laravel特定配置
    if ! grep -q "RewriteEngine On" "$APACHE_CONFIG"; then
        log_info "添加Laravel重写规则..."
        
        # 在Directory块中添加重写规则
        sed -i "/<Directory.*$PUBLIC_DIR>/,/<\/Directory>/ {
            /<\/Directory>/i\\
    # Laravel URL重写\\
    RewriteEngine On\\
    RewriteCond %{REQUEST_FILENAME} !-f\\
    RewriteCond %{REQUEST_FILENAME} !-d\\
    RewriteRule ^(.*)$ index.php [QSA,L]
        }" "$APACHE_CONFIG"
        
        log_success "Laravel重写规则已添加"
    fi
    
    # 测试Apache配置
    if apache2ctl configtest; then
        log_success "Apache配置测试通过"
        systemctl restart apache2
    else
        log_error "Apache配置有错误"
        apache2ctl configtest
    fi
else
    log_error "未找到Apache配置文件"
fi

log_step "第4步：修复文件权限"
echo "-----------------------------------"

log_info "设置正确的文件权限..."

# 设置项目权限
chown -R besthammer_c_usr:besthammer_c_usr "$PROJECT_DIR"
chmod -R 755 "$PROJECT_DIR"

# 设置Laravel特殊权限
chmod -R 775 "$PROJECT_DIR/storage"
chmod -R 775 "$PROJECT_DIR/bootstrap/cache"

# 确保public目录权限
chmod 755 "$PUBLIC_DIR"
chmod 644 "$PUBLIC_DIR/index.php"

log_success "文件权限已设置"

log_step "第5步：检查和修复Laravel配置"
echo "-----------------------------------"

# 检查.env文件
if [ -f "$PROJECT_DIR/.env" ]; then
    log_success ".env文件存在"
    
    # 检查APP_KEY
    if grep -q "APP_KEY=base64:" "$PROJECT_DIR/.env"; then
        log_success "APP_KEY已设置"
    else
        log_warning "APP_KEY未设置或格式错误"
        
        # 尝试生成APP_KEY
        cd "$PROJECT_DIR"
        if command -v php &> /dev/null && [ -f "artisan" ]; then
            log_info "生成Laravel APP_KEY..."
            sudo -u besthammer_c_usr php artisan key:generate --force
            log_success "APP_KEY已生成"
        fi
    fi
    
    # 检查APP_URL
    if grep -q "APP_URL=https://www.besthammer.club" "$PROJECT_DIR/.env"; then
        log_success "APP_URL配置正确"
    else
        log_warning "APP_URL配置可能错误"
        sed -i 's|APP_URL=.*|APP_URL=https://www.besthammer.club|g' "$PROJECT_DIR/.env"
        log_success "APP_URL已修复"
    fi
    
    # 检查APP_DEBUG
    if grep -q "APP_DEBUG=true" "$PROJECT_DIR/.env"; then
        log_info "调试模式已启用（有助于查看详细错误）"
    else
        log_info "启用调试模式以查看详细错误..."
        sed -i 's|APP_DEBUG=.*|APP_DEBUG=true|g' "$PROJECT_DIR/.env"
    fi
else
    log_error ".env文件不存在"
    if [ -f "$PROJECT_DIR/.env.example" ]; then
        log_info "从.env.example创建.env文件..."
        cp "$PROJECT_DIR/.env.example" "$PROJECT_DIR/.env"
        chown besthammer_c_usr:besthammer_c_usr "$PROJECT_DIR/.env"
    fi
fi

# 清除Laravel缓存
if [ -f "$PROJECT_DIR/artisan" ]; then
    log_info "清除Laravel缓存..."
    cd "$PROJECT_DIR"
    sudo -u besthammer_c_usr php artisan config:clear 2>/dev/null || true
    sudo -u besthammer_c_usr php artisan cache:clear 2>/dev/null || true
    sudo -u besthammer_c_usr php artisan route:clear 2>/dev/null || true
    sudo -u besthammer_c_usr php artisan view:clear 2>/dev/null || true
    log_success "Laravel缓存已清除"
fi

log_step "第6步：检查PHP配置"
echo "-----------------------------------"

# 检查PHP错误日志
PHP_LOG="/var/log/php_errors.log"
if [ -f "$PHP_LOG" ]; then
    log_info "检查PHP错误日志..."
    tail -n 5 "$PHP_LOG" | grep -E "(Fatal|Error|Warning)" | tail -3 || echo "   未发现PHP错误"
fi

# 检查PHP扩展
log_info "检查PHP扩展..."
REQUIRED_EXTENSIONS=("mbstring" "openssl" "pdo" "tokenizer" "xml" "ctype" "json" "bcmath")
for ext in "${REQUIRED_EXTENSIONS[@]}"; do
    if php -m | grep -q "$ext"; then
        log_success "PHP扩展已安装: $ext"
    else
        log_warning "PHP扩展缺失: $ext"
    fi
done

log_step "第7步：创建详细错误诊断页面"
echo "-----------------------------------"

cat > "$PUBLIC_DIR/error-diagnosis.php" << 'EOF'
<?php
// 启用错误显示
error_reporting(E_ALL);
ini_set('display_errors', 1);

header('Content-Type: text/html; charset=utf-8');
?>
<!DOCTYPE html>
<html>
<head>
    <title>500错误诊断页面</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background: #f8f9fa; }
        .container { max-width: 1000px; margin: 0 auto; background: white; padding: 30px; border-radius: 10px; box-shadow: 0 4px 6px rgba(0,0,0,0.1); }
        .success { color: #28a745; font-weight: bold; }
        .error { color: #dc3545; font-weight: bold; }
        .warning { color: #ffc107; font-weight: bold; }
        table { width: 100%; border-collapse: collapse; margin: 20px 0; }
        th, td { padding: 12px; text-align: left; border-bottom: 1px solid #ddd; }
        th { background-color: #f8f9fa; }
        .status-ok { background-color: #d4edda; }
        .status-error { background-color: #f8d7da; }
        .status-warning { background-color: #fff3cd; }
        pre { background: #f8f9fa; padding: 15px; border-radius: 5px; overflow-x: auto; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🔧 500错误详细诊断</h1>
        
        <h2>基础环境检查</h2>
        <table>
            <tr><th>项目</th><th>值</th><th>状态</th></tr>
            <tr class="<?php echo file_exists('../.env') ? 'status-ok' : 'status-error'; ?>">
                <td>.env文件</td>
                <td><?php echo file_exists('../.env') ? '存在' : '不存在'; ?></td>
                <td><?php echo file_exists('../.env') ? '✅ 正常' : '❌ 缺失'; ?></td>
            </tr>
            <tr class="<?php echo file_exists('../bootstrap/app.php') ? 'status-ok' : 'status-error'; ?>">
                <td>Laravel Bootstrap</td>
                <td><?php echo file_exists('../bootstrap/app.php') ? '存在' : '不存在'; ?></td>
                <td><?php echo file_exists('../bootstrap/app.php') ? '✅ 正常' : '❌ 缺失'; ?></td>
            </tr>
            <tr class="<?php echo is_writable('../storage') ? 'status-ok' : 'status-error'; ?>">
                <td>Storage权限</td>
                <td><?php echo is_writable('../storage') ? '可写' : '不可写'; ?></td>
                <td><?php echo is_writable('../storage') ? '✅ 正常' : '❌ 权限错误'; ?></td>
            </tr>
            <tr class="status-ok">
                <td>PHP版本</td>
                <td><?php echo PHP_VERSION; ?></td>
                <td>✅ 正常</td>
            </tr>
        </table>
        
        <h2>Laravel扩展检查</h2>
        <table>
            <tr><th>扩展</th><th>状态</th></tr>
            <?php
            $required_extensions = ['mbstring', 'openssl', 'pdo', 'tokenizer', 'xml', 'ctype', 'json', 'bcmath'];
            foreach ($required_extensions as $ext) {
                $loaded = extension_loaded($ext);
                $status_class = $loaded ? 'status-ok' : 'status-error';
                $status_text = $loaded ? '✅ 已加载' : '❌ 未加载';
                echo "<tr class='$status_class'><td>$ext</td><td>$status_text</td></tr>";
            }
            ?>
        </table>
        
        <h2>尝试加载Laravel</h2>
        <div style="background: #f8f9fa; padding: 20px; border-radius: 5px; margin: 20px 0;">
            <?php
            try {
                // 尝试加载Laravel
                if (file_exists('../bootstrap/app.php')) {
                    echo "<p class='success'>✅ 尝试加载Laravel应用...</p>";
                    
                    // 检查autoload
                    if (file_exists('../vendor/autoload.php')) {
                        echo "<p class='success'>✅ Composer autoload存在</p>";
                        require_once '../vendor/autoload.php';
                        
                        // 尝试创建应用实例
                        $app = require_once '../bootstrap/app.php';
                        echo "<p class='success'>✅ Laravel应用实例创建成功</p>";
                        
                        // 检查.env
                        if (file_exists('../.env')) {
                            echo "<p class='success'>✅ .env文件存在</p>";
                            
                            // 尝试启动应用
                            $kernel = $app->make(Illuminate\Contracts\Http\Kernel::class);
                            echo "<p class='success'>✅ HTTP Kernel创建成功</p>";
                            
                            echo "<p class='success'>🎉 Laravel应用基础组件正常！</p>";
                            echo "<p class='warning'>⚠️ 如果仍有500错误，可能是路由或控制器问题</p>";
                            
                        } else {
                            echo "<p class='error'>❌ .env文件不存在</p>";
                        }
                    } else {
                        echo "<p class='error'>❌ vendor/autoload.php不存在，需要运行 composer install</p>";
                    }
                } else {
                    echo "<p class='error'>❌ bootstrap/app.php不存在</p>";
                }
            } catch (Exception $e) {
                echo "<p class='error'>❌ Laravel加载失败：</p>";
                echo "<pre>" . htmlspecialchars($e->getMessage()) . "</pre>";
                echo "<p class='warning'>详细错误信息：</p>";
                echo "<pre>" . htmlspecialchars($e->getTraceAsString()) . "</pre>";
            }
            ?>
        </div>
        
        <h2>服务器信息</h2>
        <table>
            <tr><th>项目</th><th>值</th></tr>
            <tr><td>文档根目录</td><td><?php echo $_SERVER['DOCUMENT_ROOT']; ?></td></tr>
            <tr><td>脚本文件名</td><td><?php echo $_SERVER['SCRIPT_FILENAME']; ?></td></tr>
            <tr><td>服务器软件</td><td><?php echo $_SERVER['SERVER_SOFTWARE']; ?></td></tr>
            <tr><td>PHP SAPI</td><td><?php echo php_sapi_name(); ?></td></tr>
        </table>
        
        <h2>建议的解决步骤</h2>
        <ol>
            <li>如果vendor目录不存在，运行：<code>composer install</code></li>
            <li>如果.env文件有问题，运行：<code>php artisan key:generate</code></li>
            <li>检查storage目录权限：<code>chmod -R 775 storage</code></li>
            <li>清除缓存：<code>php artisan config:clear</code></li>
            <li>查看Laravel日志：<code>storage/logs/laravel.log</code></li>
        </ol>
        
        <div style="margin-top: 30px; text-align: center;">
            <a href="/" style="display: inline-block; padding: 10px 20px; background: #007bff; color: white; text-decoration: none; border-radius: 5px;">🏠 尝试访问首页</a>
        </div>
        
        <hr style="margin: 30px 0;">
        <p style="text-align: center; color: #6c757d;">
            <small>诊断时间: <?php echo date('Y-m-d H:i:s T'); ?></small>
        </p>
    </div>
</body>
</html>
EOF

chown besthammer_c_usr:besthammer_c_usr "$PUBLIC_DIR/error-diagnosis.php"
log_success "错误诊断页面创建完成"

echo ""
echo "🎉 500错误修复完成！"
echo "===================="
echo ""
echo "📋 修复摘要："
echo "✅ Apache DocumentRoot已修复"
echo "✅ 文件权限已设置"
echo "✅ Laravel配置已检查"
echo "✅ 缓存已清除"
echo "✅ 错误诊断页面已创建"
echo ""
echo "🧪 详细诊断页面："
echo "   https://www.besthammer.club/error-diagnosis.php"
echo ""
echo "🎯 如果诊断页面显示Laravel组件正常，但仍有500错误："
echo "   1. 检查Laravel日志: storage/logs/laravel.log"
echo "   2. 检查路由文件: routes/web.php"
echo "   3. 检查控制器文件"
echo ""
echo "🔍 如果诊断页面显示组件异常："
echo "   1. 运行 composer install"
echo "   2. 运行 php artisan key:generate"
echo "   3. 检查.env文件配置"
echo ""
log_info "500错误修复完成！请访问诊断页面查看详细信息！"

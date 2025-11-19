#!/bin/sh
# Docker 容器内自动更新认证信息脚本（直接挂载模式）

set -e

# 配置文件路径
FNNAS_CONFIG_FILE="${FNNAS_CONFIG_PATH:-/app/fnnas-config.json}"
ENV_FILE="/app/.env"
LOG_FILE="/var/log/cron/update-auth.log"

# 日志函数
# 直接输出到 stdout，让调用者（cron 或手动执行）处理重定向
# date 命令会自动使用系统时区（已在 entrypoint 中设置为北京时间）
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# 从挂载的配置文件获取认证信息
get_auth_from_file() {
    local config_file="$1"
    
    if [ ! -f "$config_file" ]; then
        log "错误: 配置文件 $config_file 不存在"
        log "提示: 请检查 docker-compose.yml 中的挂载配置："
        log "      - ${FNNAS_CONFIG_PATH:-/root/.docker/config.json}:/app/fnnas-config.json:ro"
        log "      确保宿主机路径存在且可访问"
        log "      如果路径不同，请在 .env 文件中设置 FNNAS_CONFIG_PATH 或在 docker-compose.yml 中修改"
        return 1
    fi
    
    if ! command -v jq >/dev/null 2>&1; then
        log "错误: 未安装 jq"
        return 1
    fi
    
    META_TOKEN=$(jq -r '.HttpHeaders."X-Meta-Token"' "$config_file" 2>/dev/null || echo "")
    META_SIGN=$(jq -r '.HttpHeaders."X-Meta-Sign"' "$config_file" 2>/dev/null || echo "")
    
    if [ -z "$META_TOKEN" ] || [ "$META_TOKEN" = "null" ] || [ -z "$META_SIGN" ] || [ "$META_SIGN" = "null" ]; then
        log "错误: 无法从配置文件获取有效的认证信息"
        return 1
    fi
    
    return 0
}

# 更新 .env 文件和 Nginx 配置
update_config() {
    # 读取当前 .env 文件中的值
    local current_token=$(grep "^META_TOKEN=" "$ENV_FILE" 2>/dev/null | cut -d'=' -f2- || echo "")
    local current_sign=$(grep "^META_SIGN=" "$ENV_FILE" 2>/dev/null | cut -d'=' -f2- || echo "")
    
    # 检查是否有变化
    if [ "$current_token" = "$META_TOKEN" ] && [ "$current_sign" = "$META_SIGN" ]; then
        log "认证信息未变化，无需更新"
        return 0
    fi
    
    log "检测到认证信息变化，开始更新..."
    log "Token: ${META_TOKEN:0:20}..."
    log "Sign: ${META_SIGN:0:10}..."
    
    # 备份原文件
    cp "$ENV_FILE" "${ENV_FILE}.bak" 2>/dev/null || true
    
    # 更新 .env 文件（使用临时文件避免 Resource busy 错误）
    # 创建临时文件
    local temp_file=$(mktemp)
    
    # 读取原文件，替换或添加 META_TOKEN 和 META_SIGN
    local token_found=false
    local sign_found=false
    
    while IFS= read -r line || [ -n "$line" ]; do
        if echo "$line" | grep -q "^META_TOKEN="; then
            echo "META_TOKEN=$META_TOKEN" >> "$temp_file"
            token_found=true
        elif echo "$line" | grep -q "^META_SIGN="; then
            echo "META_SIGN=$META_SIGN" >> "$temp_file"
            sign_found=true
        else
            echo "$line" >> "$temp_file"
        fi
    done < "$ENV_FILE"
    
    # 如果原文件中没有这些行，添加它们
    if [ "$token_found" = "false" ]; then
        echo "META_TOKEN=$META_TOKEN" >> "$temp_file"
    fi
    if [ "$sign_found" = "false" ]; then
        echo "META_SIGN=$META_SIGN" >> "$temp_file"
    fi
    
    # 使用 cat 写入原文件（避免 sed -i 的 Resource busy 问题）
    cat "$temp_file" > "$ENV_FILE"
    rm -f "$temp_file"
    
    log ".env 文件已更新"
    
    # 重新生成 nginx 配置
    log "重新生成 nginx 配置..."
    
    # 从更新后的 .env 文件读取新的认证信息
    export $(grep -v '^#' "$ENV_FILE" | grep -E '^(META_TOKEN|META_SIGN)=' | xargs)
    
    # 重新生成配置
    cp /etc/nginx/templates/default.conf.template /tmp/default.conf.template
    sed -i "s|\${META_TOKEN}|${META_TOKEN}|g" /tmp/default.conf.template
    sed -i "s|\${META_SIGN}|${META_SIGN}|g" /tmp/default.conf.template
    
    # 设置日志配置
    if [ "${ENABLE_ACCESS_LOG}" = "true" ]; then
        ACCESS_LOG_CONFIG="/var/log/nginx/${ACCESS_LOG_NAME:-http-proxy-access.log}"
    else
        ACCESS_LOG_CONFIG="off"
    fi
    
    if [ "${ENABLE_ERROR_LOG}" = "true" ]; then
        ERROR_LOG_CONFIG="/var/log/nginx/${ERROR_LOG_NAME:-http-proxy-error.log}"
    else
        ERROR_LOG_CONFIG="off"
    fi
    
    sed -i "s|\${ACCESS_LOG_CONFIG}|${ACCESS_LOG_CONFIG}|g" /tmp/default.conf.template
    sed -i "s|\${ERROR_LOG_CONFIG}|${ERROR_LOG_CONFIG}|g" /tmp/default.conf.template
    
    # 复制到目标位置
    cp /tmp/default.conf.template /etc/nginx/conf.d/default.conf
    
    # 如果是启动时的更新，nginx 还没有启动，不需要重新加载
    if [ "${STARTUP_UPDATE:-false}" = "true" ]; then
        log "启动时更新：配置文件已生成，nginx 将在启动时使用新配置"
        return 0
    fi
    
    # 测试并重新加载 nginx 配置（仅在运行时更新时）
    if nginx -t >/dev/null 2>&1; then
        nginx -s reload
        log "Nginx 配置已重新加载"
    else
        log "错误: Nginx 配置测试失败"
        nginx -t
        return 1
    fi
    
    log "✅ 认证信息更新完成"
    return 0
}

# 主函数
main() {
    # 确保日志目录存在
    mkdir -p "$(dirname "$LOG_FILE")"
    
    log "=========================================="
    log "开始更新认证信息"
    log "配置文件: $FNNAS_CONFIG_FILE"
    
    # 先检查文件是否存在，给出更详细的提示
    if [ ! -f "$FNNAS_CONFIG_FILE" ]; then
        log "错误: 配置文件 $FNNAS_CONFIG_FILE 不存在"
        log ""
        log "解决方案："
        log "1. 确认飞牛 NAS 的配置文件路径（通常在 /root/.docker/config.json）"
        log "2. 在 docker-compose.yml 中修改挂载路径，例如："
        log "   - /root/.docker/config.json:/app/fnnas-config.json:ro"
        log "3. 或者在 .env 文件中设置 FNNAS_CONFIG_PATH 变量"
        log ""
        
        # 如果是启动时的首次更新失败，不退出（由调用者处理）
        if [ "${STARTUP_UPDATE:-false}" != "true" ]; then
            exit 1
        fi
        return 1
    fi
    
    if get_auth_from_file "$FNNAS_CONFIG_FILE"; then
        update_config
    else
        log "错误: 无法从挂载文件获取认证信息"
        # 如果是启动时的首次更新失败，不退出（由调用者处理）
        if [ "${STARTUP_UPDATE:-false}" != "true" ]; then
            exit 1
        fi
        return 1
    fi
}

# 执行主函数
main

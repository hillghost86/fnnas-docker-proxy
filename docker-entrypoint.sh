#!/bin/sh
set -e

# 设置时区为北京时间（必须在最前面，确保所有命令都使用正确时区）
if [ -n "$TZ" ]; then
    # 安装 tzdata（Alpine 默认不包含）
    if [ ! -d /usr/share/zoneinfo ]; then
        echo "安装 tzdata..."
        apk add --no-cache tzdata >/dev/null 2>&1 || true
    fi
    # 设置时区
    if [ -d /usr/share/zoneinfo ] && [ -f /usr/share/zoneinfo/$TZ ]; then
        cp /usr/share/zoneinfo/$TZ /etc/localtime 2>/dev/null || true
        echo "$TZ" > /etc/timezone 2>/dev/null || true
        export TZ
        echo "时区已设置为: $TZ ($(date '+%Z %z'))"
    else
        echo "警告: 无法设置时区 $TZ，使用默认时区"
    fi
else
    # 如果没有设置 TZ，默认使用北京时间
    if [ ! -d /usr/share/zoneinfo ]; then
        apk add --no-cache tzdata >/dev/null 2>&1 || true
    fi
    if [ -f /usr/share/zoneinfo/Asia/Shanghai ]; then
        cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime 2>/dev/null || true
        echo "Asia/Shanghai" > /etc/timezone 2>/dev/null || true
        export TZ=Asia/Shanghai
        echo "时区已设置为: Asia/Shanghai ($(date '+%Z %z'))"
    fi
fi

# 如果日志目录挂载存在，确保目录可写
if [ -d "/var/log/nginx" ]; then
    chmod 755 /var/log/nginx 2>/dev/null || true
fi

# 如果启用了自动更新，安装必要工具并启动 cron
if [ "${ENABLE_AUTO_UPDATE}" = "true" ]; then
    # 安装必要的工具（如果未安装）
    if ! command -v jq >/dev/null 2>&1; then
        echo "安装 jq..."
        apk add --no-cache jq >/dev/null 2>&1 || true
    fi
    if ! command -v crond >/dev/null 2>&1; then
        echo "安装 dcron..."
        apk add --no-cache dcron >/dev/null 2>&1 || true
    fi
    
    # 确保日志目录存在
    mkdir -p /var/log/cron
    
    # 启动时先执行一次更新，获取认证信息
    echo "启动时执行首次认证信息更新..."
    STARTUP_UPDATE=true sh /app/scripts/update-auth.sh 2>&1 | tee -a /var/log/cron/update-auth.log || {
        echo "警告: 启动时更新失败，使用 .env 文件中的初始值（如果有）"
        # 如果 .env 中的值为空，使用占位符
        if [ -z "$META_TOKEN" ] || [ -z "$META_SIGN" ]; then
            echo "警告: .env 文件中认证信息为空，使用占位符"
            export META_TOKEN="placeholder_token"
            export META_SIGN="placeholder_sign"
        fi
    }
    
    # 从更新后的 .env 文件重新读取认证信息（如果更新成功）
    if [ -f /app/.env ]; then
        export $(grep -v '^#' /app/.env | grep -E '^(META_TOKEN|META_SIGN)=' | xargs)
    fi
    
    # 设置并启动 cron 服务（后台运行）
    sh /app/scripts/setup-cron.sh &
fi

# 复制模板文件到临时位置
cp /etc/nginx/templates/default.conf.template /tmp/default.conf.template

# 替换配置文件中的环境变量
sed -i "s|\${META_TOKEN}|${META_TOKEN}|g" /tmp/default.conf.template
sed -i "s|\${META_SIGN}|${META_SIGN}|g" /tmp/default.conf.template

# 根据环境变量设置日志配置
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

# 替换日志配置占位符
sed -i "s|\${ACCESS_LOG_CONFIG}|${ACCESS_LOG_CONFIG}|g" /tmp/default.conf.template
sed -i "s|\${ERROR_LOG_CONFIG}|${ERROR_LOG_CONFIG}|g" /tmp/default.conf.template

# 将处理后的配置复制到目标位置
cp /tmp/default.conf.template /etc/nginx/conf.d/default.conf

# 执行 nginx
exec nginx -g 'daemon off;'

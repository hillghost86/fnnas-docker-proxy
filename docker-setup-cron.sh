#!/bin/sh
# 在容器内设置定时任务

# 更新间隔（秒），默认 1 小时
UPDATE_INTERVAL="${UPDATE_INTERVAL:-3600}"
UPDATE_MINUTES=$((UPDATE_INTERVAL / 60))

# 确保日志目录存在
mkdir -p /var/log/cron

    # 创建 cron 任务（使用 sh 执行，避免权限问题）
    # 使用 tee 同时输出到文件和控制台
    # tee 的语法：tee [选项] 文件1 文件2（同时写入多个文件）
    CRON_JOB="*/${UPDATE_MINUTES} * * * * sh /app/scripts/update-auth.sh 2>&1 | tee -a /var/log/cron/update-auth.log /proc/1/fd/1"

# 写入 crontab
echo "$CRON_JOB" | crontab -

# 启动 cron 服务（后台运行）
crond -l 2


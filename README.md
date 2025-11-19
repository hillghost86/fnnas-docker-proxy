# fnnas-docker-proxy

![License](https://img.shields.io/badge/license-MIT-blue.svg)
![Docker](https://img.shields.io/badge/docker-ready-blue.svg)
![Nginx](https://img.shields.io/badge/nginx-proxy-green.svg)

[![GitHub](https://img.shields.io/badge/GitHub-hillghost86%2Ffnnas--docker--proxy-blue?logo=github)](https://github.com/hillghost86/fnnas-docker-proxy)
[![Gitee](https://img.shields.io/badge/Gitee-hillghost86%2Ffnnas--docker--proxy-red?logo=gitee)](https://gitee.com/hillghost86/fnnas-docker-proxy)

> 使用 Nginx 反向代理为飞牛 NAS (FNNAS) 的 Docker Registry 添加自定义认证 headers，实现局域网内 Docker 镜像加速。



通过 Nginx 反向代理飞牛 NAS 的 Docker Registry，自动添加认证 headers，支持**自动更新认证信息**，实现局域网内 Docker 镜像加速。

> **⚠️ 重要提示**：本项目**仅限在飞牛 NAS 上使用**。因为需要直接挂载飞牛 NAS 的配置文件（`/root/.docker/config.json`）来获取认证信息，所以 Docker 容器必须在飞牛 NAS 上运行。不支持在其他系统上使用。

## 📋 目录

- [功能特性](#-功能特性)
- [快速开始](#-快速开始)
- [自动更新功能](#-自动更新功能)
- [配置说明](#-配置说明)
- [文件说明](#-文件说明)
- [工作原理](#-工作原理)
- [故障排查](#-故障排查)
- [注意事项](#-注意事项)

## ✨ 功能特性

- ✅ **自动添加认证 headers** - 自动添加 `X-Meta-Token` 和 `X-Meta-Sign` 认证 headers
- ✅ **自动更新认证信息** - 支持自动检测并更新变化的认证信息，无需手动干预
- ✅ **重写认证头** - 重写 `WWW-Authenticate` header，确保 Docker 通过代理获取 token
- ✅ **HTTP 协议支持** - 支持 HTTP 协议，无需配置 SSL 证书
- ✅ **局域网部署** - 支持局域网部署（监听 `0.0.0.0:15000`）

## 🚀 快速开始

> **📌 使用前提**：本项目必须在**飞牛 NAS 上运行**，因为需要挂载飞牛 NAS 的配置文件来获取认证信息。请确保你的 Docker 环境运行在飞牛 NAS 上。

### 1. 克隆仓库

使用 Git 克隆本项目到本地，可以选择以下任一方式：

**GitHub（推荐）：**

```bash
# HTTPS 方式
git clone https://github.com/hillghost86/fnnas-docker-proxy.git
cd fnnas-docker-proxy
```

```bash
# SSH 方式
git clone git@github.com:hillghost86/fnnas-docker-proxy.git
cd fnnas-docker-proxy
```

**Gitee（国内镜像，访问更快）：**

```bash
# HTTPS 方式
git clone https://gitee.com/hillghost86/fnnas-docker-proxy.git
cd fnnas-docker-proxy
```

```bash
# SSH 方式
git clone git@gitee.com:hillghost86/fnnas-docker-proxy.git
cd fnnas-docker-proxy
```

### 2. 启动服务

```bash
docker compose up -d
```

> **💡 提示**：
> - 直接使用 `nginx:alpine` 镜像，无需构建
> - 启动时会自动安装必要的工具（jq、dcron）大概需要几分钟的时间，耐心等待一会。
> - 默认启用自动更新，认证信息会在启动时自动获取
> - 所有日志使用北京时间（CST，UTC+8）
> - 浏览器访问 http://飞牛ip地址:15000/health  例如 http://192.168.1.100:15000/health 显示OK，说明服务启动成功了。此处的 192.168.1.100 替换为你飞牛的IP地址。

### 3. 配置 Docker 客户端

配置 Docker 客户端使用代理服务。编辑 Docker 配置文件：

**Linux/macOS：**
```bash
sudo nano /etc/docker/daemon.json
```

**Windows：**
编辑 `C:\ProgramData\docker\config\daemon.json`

添加以下配置：
将192.168.1.100替换为你飞牛的IP地址

```json
{
  "registry-mirrors": [
    "http://192.168.1.100:15000"
  ],
  "insecure-registries": [
    "192.168.1.100:15000"
  ]
}
```

> **💡 提示**：
> - `registry-mirrors`：配置镜像加速源
> - `insecure-registries`：允许使用 HTTP 协议（因为代理使用 HTTP）
> - 将 `192.168.1.100` 替换为飞牛服务器的 IP 地址

**重启 Docker 服务：**

```bash
# Linux
sudo systemctl restart docker

# macOS (Docker Desktop)
# 在 Docker Desktop 中重启服务

# Windows
# 在 Docker Desktop 中重启服务
```

**验证配置：**

```bash
docker info | grep -A 10 "Registry Mirrors"
```

应该看到：
```
Registry Mirrors:
 http://192.168.1.100:15000/
```


## 自定义配置

以下配置信息为可选项，建议直接使用默认配置。

### 1. 配置 docker-compose

编辑 `docker-compose.yml`，确认挂载配置（可选，默认已经使用了飞牛docker的默认路径。）：

```yaml
volumes:
  # 挂载飞牛 NAS 的配置文件（默认路径，如果不同请修改）
  - /root/.docker/config.json:/app/fnnas-config.json:ro
```

如果飞牛 NAS 的配置文件路径不是 `/root/.docker/config.json`，可以通过环境变量指定：

在 `.env` 文件中设置：
```env
FNNAS_CONFIG_PATH=/你的实际路径/config.json
```

然后在 `docker-compose.yml` 中使用：
```yaml
- ${FNNAS_CONFIG_PATH}:/app/fnnas-config.json:ro
```

### 2. 配置 .env 文件（可选）

项目已提供默认的 `.env` 文件，**默认启用自动更新**，可以直接使用，无需修改。

如果需要自定义配置，可以编辑 `.env` 文件：

```env
# 启用自动更新（推荐，默认已启用）
ENABLE_AUTO_UPDATE=true

# 更新间隔（秒），默认 3600（1小时）
UPDATE_INTERVAL=3600

# 认证信息（启用自动更新时可以为空，启动时会自动获取）
META_TOKEN=
META_SIGN=
```

> **💡 提示**：
> - 默认配置已启用自动更新（`ENABLE_AUTO_UPDATE=true`），`META_TOKEN` 和 `META_SIGN` 可以为空
> - 系统会在启动时自动从挂载的配置文件获取认证信息
> - 如果未启用自动更新，需要手动填写 `META_TOKEN` 和 `META_SIGN` 的值

---

## 🔄 自动更新功能

### 工作原理

```
容器启动
  ↓
定时任务（cron）
  ↓
读取挂载的配置文件
  ↓
提取认证信息
  ↓
更新 .env 文件
  ↓
重新生成 Nginx 配置
  ↓
nginx -s reload（无需重启容器）
```

### 查看更新日志

```bash
# 查看更新日志
docker compose exec nginx-proxy tail -f /var/log/cron/update-auth.log

# 或者查看宿主机日志文件
tail -f logs/update-auth.log
```

### 手动触发更新

```bash
# 手动触发更新（会显示在容器日志中）
docker compose exec nginx-proxy sh /app/scripts/update-auth.sh

# 查看更新结果
docker compose logs | tail -20
```

---

## ⚙️ 配置说明

### 环境变量

| 变量 | 说明 | 默认值 |
|------|------|--------|
| `ENABLE_AUTO_UPDATE` | 是否启用自动更新 | `true` |
| `UPDATE_INTERVAL` | 更新间隔（秒） | `3600` |
| `FNNAS_CONFIG_PATH` | 飞牛 NAS 配置文件路径（容器内） | `/app/fnnas-config.json` |
| `ENABLE_ACCESS_LOG` | 是否开启访问日志 | `false` |
| `ENABLE_ERROR_LOG` | 是否开启错误日志 | `false` |
| `TZ` | 时区设置 | `Asia/Shanghai` |

### 挂载路径

| 宿主机路径 | 容器路径 | 说明 |
|-----------|---------|------|
| `/root/.docker/config.json` | `/app/fnnas-config.json` | 飞牛 NAS 配置文件（只读） |
| `.env` | `/app/.env` | 环境变量文件（可写） |
| `logs/` | `/var/log/cron` | 更新日志目录 |

---

## 📁 文件说明

| 文件 | 说明 |
|------|------|
| `docker-compose.yml` | Docker Compose 配置文件 |
| `docker-entrypoint.sh` | 启动脚本（支持自动更新，启动时安装必要工具） |
| `docker-update-auth.sh` | 更新脚本（直接挂载模式） |
| `docker-setup-cron.sh` | Cron 定时任务设置脚本 |
| `nginx-http-proxy.conf` | Nginx 代理配置模板 |
| `env.example` | 环境变量配置示例文件 |

---

## 🔧 工作原理

1. **Docker 请求** - Docker 请求 `http://127.0.0.1:15000/v2/...`
2. **Nginx 代理** - Nginx 代理到 `https://docker.fnnas.com`，自动添加认证 headers
3. **重写认证头** - 返回的 `WWW-Authenticate` header 被重写为 `http://127.0.0.1:15000/service/token`
4. **完成拉取** - Docker 使用重写后的地址获取 token，继续通过代理完成镜像拉取
5. **自动更新** - 定时任务自动检测认证信息变化，更新配置并重新加载 Nginx

---

## 🔍 故障排查

### 检查代理服务状态

```bash
docker compose ps
docker compose logs
```

### 检查配置文件是否挂载

```bash
# 检查配置文件是否挂载
docker compose exec nginx-proxy ls -la /app/fnnas-config.json

# 检查文件内容
docker compose exec nginx-proxy cat /app/fnnas-config.json
```

### 查看更新日志

定时任务的日志会同时显示在容器日志和日志文件中：

```bash
# 查看容器日志（推荐，可以看到实时更新）
docker compose logs -f

# 查看更新日志文件
docker compose exec nginx-proxy tail -f /var/log/cron/update-auth.log

# 或者查看宿主机日志文件
tail -f logs/update-auth.log
```

### 查看 cron 状态

```bash
# 查看 cron 进程
docker compose exec nginx-proxy ps aux | grep cron

# 查看 crontab
docker compose exec nginx-proxy crontab -l
```

### 测试代理响应

```bash
curl -v http://127.0.0.1:15000/v2/
```

应该返回 unauthorized: unauthorized ，但 `WWW-Authenticate` header 应该指向 `http://127.0.0.1:15000/service/token`。

### 测试 Docker 拉取镜像

```bash
# 测试拉取镜像（使用代理）
docker pull alpine:latest

# 查看镜像信息
docker images | grep alpine
```

如果配置正确，镜像会通过代理加速拉取。

---

## ⚠️ 注意事项

1. **文件权限**：
   - 确保容器可以读取挂载的配置文件
   - 检查文件路径是否正确

2. **更新频率**：
   - 不要设置太频繁的更新间隔，建议至少 10 分钟

3. **日志管理**：
   - 定期清理更新日志，避免占用过多空间

4. **认证信息**：
   - 存储在 `.env` 文件中，默认配置已提交到仓库（启用自动更新，认证信息为空）
   - 如果启用了自动更新，系统会在启动时自动获取并更新认证信息
   - 如果未启用自动更新，需要手动填写 `META_TOKEN` 和 `META_SIGN` 的值

5. **配置文件路径**：
   - 默认路径是 `/root/.docker/config.json`
   - 如果路径不同，需要在 `docker-compose.yml` 中修改挂载路径

6. **时区设置**：
   - 默认使用北京时间（Asia/Shanghai，CST，UTC+8）
   - 所有日志时间戳都使用北京时间
   - 可以通过 `TZ` 环境变量修改时区

---

**⭐ 如果这个项目对你有帮助，欢迎 Star！**

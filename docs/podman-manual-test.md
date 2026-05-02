# Podman 原生脚本手工测试手册

本文档面向在本地用原生 `podman` CLI 手工验证 `chrono-synth-deploy` 的开发者。目标不是解释实现细节，而是给出一条可重复执行的标准测试路径。

## 1. 测试目标

完成一次完整手工测试后，应确认以下结论：

1. `chrono-synth-os` 与 `chrono-synth-web` 镜像可以在本地构建成功。
2. `deploy.sh podman up` 会自动拉起完整企业拓扑，而不是依赖任何 Compose 层。
3. 前端、后端、独立 worker、Redpanda、Prometheus、Grafana、Jaeger 均可访问。
4. 认证、企业控制面、SCIM、Organizations、Persona Core、Marketplace、Audit、Avatar Autorun、Observability 主链路可跑通。
5. 失败时能够定位到具体脚本、容器、端口或依赖。

## 2. 前置条件

### 2.1 主机要求

- `podman` 已安装且可执行。
- `podman info` 能成功返回。
- 若使用 Podman Machine，先执行 `podman machine start`。
- 本机具备 `curl`。
- 建议具备 `jq`，便于人工查看 JSON 返回。

### 2.2 源码目录要求

默认约定三个仓库为同级目录：

```text
.../IdeaProjects/
├── chrono-synth-os/
├── chrono-synth-web/
└── chrono-synth-deploy/
```

若你的目录不同，需在执行构建前额外设置：

```bash
export BACKEND_SRC=/abs/path/to/chrono-synth-os
export FRONTEND_SRC=/abs/path/to/chrono-synth-web
```

### 2.3 基线自检

在 `chrono-synth-deploy` 仓库根目录执行：

```bash
pwd
podman info
podman ps -a
```

预期：

- `podman info` 成功。
- 当前不存在与 `chrono-synth-*` 冲突的旧容器；如果存在，先执行 `./deploy.sh podman down`。

## 3. 配置准备

### 3.1 生成本地环境文件

```bash
cp podman/.env.example podman/.env
```

至少检查以下变量：

| 变量 | 建议值 | 说明 |
| --- | --- | --- |
| `BACKEND_PORT` | `3100` | 后端 API 映射端口 |
| `FRONTEND_PORT` | `8088` | 前端统一入口 |
| `JAEGER_PORT` | `16686` | Jaeger UI |
| `SERVER_PUBLIC_URL` | `http://localhost:8088` | 必须与前端公开访问地址一致 |
| `JWT_SECRET` | 任意本地安全值 | JWT 签名密钥 |
| `METRICS_SCRAPE_KEY` | 任意本地随机值 | Prometheus 抓取后端 metrics 的 token |
| `ENCRYPTION_MASTER_KEY` | `openssl rand -base64 32` 的输出 | 本地加密主密钥，必须是解码后正好 32 字节的 base64 |
| `ENCRYPTION_KEYRING_JSON` | 合法 JSON，如 `{"tenant_e2e_key":"..."}` | 本地企业控制面 `tenant_dedicated` keyring；不配置则 dedicated profile 会因未知 `kmsKeyRef` 失败 |
| `ENTERPRISE_E2E_KMS_KEY_REF` | `tenant_e2e_key` | E2E 中写入 deployment profile 的租户 key ref，应与 keyring 对齐 |

如需手工生成一份新的本地加密主密钥：

```bash
openssl rand -base64 32
```
| `INTELLIGENCE_API_KEY` | 可选 | 手测 Avatar Autorun/LLM 时建议填写 |
| `STRIPE_ENABLED` | `false` | 本地默认关闭 Stripe |

### 3.2 若端口冲突

例如将前端改为 `18088`：

```bash
sed -i '' 's/^FRONTEND_PORT=.*/FRONTEND_PORT=18088/' podman/.env
sed -i '' 's|^SERVER_PUBLIC_URL=.*|SERVER_PUBLIC_URL=http://localhost:18088|' podman/.env
```

之后所有校验命令也要同步改端口，例如：

```bash
./scripts/health-check.sh http://localhost:18088
./scripts/e2e-test.sh --frontend 18088 --backend 3100 --jaeger 16686
```

## 4. 标准测试流程

### 4.1 构建镜像

```bash
./deploy.sh podman build
```

预期：

- 成功构建两个镜像：
  - `ghcr.io/wontlost-ltd/chrono-synth-os:latest`
  - `ghcr.io/wontlost-ltd/chrono-synth-web:latest`
- 命令末尾打印“构建完成”。

建议附加检查：

```bash
podman images | grep chrono-synth
```

### 4.2 启动整套本地环境

```bash
./deploy.sh podman up
```

预期启动顺序：

1. 创建 network：`chrono-synth-podman`
2. 创建 volume：
   - `chrono-synth-pg-data`
   - `chrono-synth-redis-data`
   - `chrono-synth-redpanda-data`
   - `chrono-synth-prometheus-data`
   - `chrono-synth-grafana-data`
3. 拉起并等待健康检查：
   - PostgreSQL
   - Redis
   - Redpanda
   - Jaeger
   - Backend
   - Observability Worker
   - Prometheus
   - Grafana
   - Frontend

建议执行：

```bash
podman ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
```

预期至少看到以下容器：

- `chrono-synth-backend`
- `chrono-synth-frontend`
- `chrono-synth-postgres`
- `chrono-synth-redis`
- `chrono-synth-redpanda`
- `chrono-synth-observability-worker`
- `chrono-synth-prometheus`
- `chrono-synth-grafana`
- `chrono-synth-jaeger`

### 4.3 执行健康检查脚本

```bash
./scripts/health-check.sh http://localhost:8088
```

预期检查以下路径均返回 2xx/3xx：

- `/`
- `/healthz`
- `/readyz`
- `/worker/healthz`
- `/worker/readyz`
- `/prometheus/-/healthy`
- `/grafana/api/health`

### 4.4 运行自动化 E2E 脚本

```bash
./scripts/e2e-test.sh
```

如果你改过端口：

```bash
./scripts/e2e-test.sh --frontend 8088 --backend 3100 --jaeger 16686
```

预期：

- 输出通过/失败/跳过统计。
- 失败数为 `0`。

该脚本会覆盖：

- 注册、登录、JWT 获取
- Deployment profile 更新
- SCIM token 生成与 `/scim/v2/Users`
- Organization 创建与成员角色绑定
- Values、Memories、POS API
- Persona Core / Marketplace
- 前端代理 `/api/`、`/worker/`、`/prometheus/`、`/grafana/`
- Audit 与 worker Kafka 模式指标
- Avatar、Knowledge Sources、Autorun、Snapshot

## 5. 建议的人工补充验证

自动化脚本通过后，建议再做下面这些人工确认。

### 5.1 前端入口

打开：

- `http://localhost:8088/`
- `http://localhost:8088/enterprise`
- `http://localhost:8088/persona-core`
- `http://localhost:8088/marketplace`

确认：

- 页面能加载，不是 Nginx 默认页或空白页。
- 浏览器刷新 SPA 路径仍返回前端应用，而不是 404。

### 5.2 后端与代理接口

```bash
curl http://localhost:3100/healthz
curl http://localhost:3100/readyz
curl http://localhost:8088/healthz
curl http://localhost:8088/worker/healthz
curl http://localhost:8088/prometheus/-/healthy
curl http://localhost:8088/grafana/api/health
```

### 5.3 Worker Kafka 模式

```bash
curl http://localhost:8088/worker/metrics | grep chrono_observability_worker_mode
```

预期至少包含：

```text
chrono_observability_worker_mode{mode="kafka"} 1
```

若你是首次在本地跑完整 E2E，确认 `podman/.env` 中的 `REDPANDA_BOOTSTRAP_TOPICS` 至少包含：

```text
observability.events tenant-e2e.observability.events
```

这样 worker 启动时就能立即订阅到租户观测 topic，不会错过本轮测试生成的 rollup 指标。

### 5.4 Jaeger

```bash
open http://localhost:16686/
curl http://localhost:16686/api/services
```

若 `api/services` 已返回 `data` 字段，则说明 Jaeger UI/API 可用。即使 traces 尚少，只要页面和 API 正常即可认为部署链路可用。

### 5.5 Grafana

打开：

```text
http://localhost:8088/grafana/d/chrono-synth-overview/chrono-synth-enterprise-overview
```

确认：

- 可以进入 Grafana。
- 默认账号密码与 `.env` 中的 `GRAFANA_ADMIN_USER` / `GRAFANA_ADMIN_PASSWORD` 一致。
- Dashboard 已自动 provision。

## 6. 日志检查

当某一步失败时，优先跟随对应容器日志。

```bash
./deploy.sh podman logs backend
./deploy.sh podman logs worker
./deploy.sh podman logs frontend
./deploy.sh podman logs redpanda
./deploy.sh podman logs prometheus
./deploy.sh podman logs grafana
./deploy.sh podman logs postgres
./deploy.sh podman logs redis
./deploy.sh podman logs jaeger
```

如果只想看最近输出：

```bash
podman logs --tail 200 chrono-synth-backend
podman logs --tail 200 chrono-synth-observability-worker
```

## 7. 常用诊断命令

### 7.1 容器健康状态

```bash
podman inspect --format '{{.State.Status}} {{if .State.Health}}{{.State.Health.Status}}{{else}}no-health{{end}}' chrono-synth-backend
podman inspect --format '{{.State.Status}} {{if .State.Health}}{{.State.Health.Status}}{{else}}no-health{{end}}' chrono-synth-observability-worker
```

### 7.2 网络别名

```bash
podman inspect --format '{{range .NetworkSettings.Networks}}{{.IPAddress}} {{.Aliases}}{{end}}' chrono-synth-backend
```

预期别名包括 `backend`，这样前端代理和其他容器才能通过内部 DNS 访问它。

### 7.3 检查卷

```bash
podman volume ls | grep chrono-synth
```

### 7.4 容器内执行命令

```bash
podman exec chrono-synth-redpanda rpk cluster health -X admin.hosts=127.0.0.1:9644
podman exec chrono-synth-postgres pg_isready -U chrono -d chrono_synth
podman exec chrono-synth-redis redis-cli ping
```

## 8. 清理与重置

### 8.1 标准下线

```bash
./deploy.sh podman down
```

效果：

- 删除所有 `chrono-synth-*` 容器
- 删除 `chrono-synth-podman` 网络
- 保留各数据卷

### 8.2 完全重置卷数据

若你需要从零开始复现一次“全新环境”：

```bash
./deploy.sh podman down
podman volume rm \
  chrono-synth-pg-data \
  chrono-synth-redis-data \
  chrono-synth-redpanda-data \
  chrono-synth-prometheus-data \
  chrono-synth-grafana-data
```

注意：这会清空数据库、缓存、Kafka 数据和 Grafana/Prometheus 持久化数据。

## 9. 一次完整人工测试的最小命令清单

```bash
cd /Users/rpang/IdeaProjects/chrono-synth-deploy
cp podman/.env.example podman/.env
podman info
./deploy.sh podman build
./deploy.sh podman up
./scripts/health-check.sh http://localhost:8088
./scripts/e2e-test.sh
./deploy.sh podman logs worker
./deploy.sh podman down
```

如果你在手工测试中遇到异常，请继续对照 [podman-reference.md](podman-reference.md) 的变量与排障章节。

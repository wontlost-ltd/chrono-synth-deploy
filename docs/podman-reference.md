# Podman 原生脚本参考与排障

本文档汇总 `chrono-synth-deploy` 当前原生 Podman 脚本的入口、环境变量、容器映射与常见故障处理方式。

## 1. 脚本入口总览

### 1.1 `deploy.sh`

仓库统一入口：

```bash
./deploy.sh k3s [dev|staging|prod]
./deploy.sh podman [build|up|down|logs] [service]
./deploy.sh build [--push]
./deploy.sh status
./deploy.sh secrets
```

其中本地 Podman 分支最终委托给：

```bash
./scripts/podman-native.sh [build|up|down|logs] [service]
```

### 1.2 `scripts/build-images.sh`

作用：

- 构建 `chrono-synth-os` 镜像
- 构建 `chrono-synth-web` 镜像

默认镜像名：

- `ghcr.io/wontlost-ltd/chrono-synth-os:latest`
- `ghcr.io/wontlost-ltd/chrono-synth-web:latest`

### 1.3 `scripts/health-check.sh`

作用：

- 轮询前端首页和后端 `/healthz`
- 再依次校验 frontend proxy 后的各健康端点

用法：

```bash
./scripts/health-check.sh http://localhost:8088
```

### 1.4 `scripts/e2e-test.sh`

作用：

- 跑完整业务与企业链路脚本测试

用法：

```bash
./scripts/e2e-test.sh
./scripts/e2e-test.sh --frontend 8088 --backend 3100 --jaeger 16686
```

## 2. `podman logs` 支持的服务名

```bash
./deploy.sh podman logs backend
./deploy.sh podman logs frontend
./deploy.sh podman logs postgres
./deploy.sh podman logs redis
./deploy.sh podman logs jaeger
./deploy.sh podman logs redpanda
./deploy.sh podman logs worker
./deploy.sh podman logs prometheus
./deploy.sh podman logs grafana
```

对应容器名如下：

| service 参数 | 容器名 |
| --- | --- |
| `backend` | `chrono-synth-backend` |
| `frontend` | `chrono-synth-frontend` |
| `postgres` | `chrono-synth-postgres` |
| `redis` | `chrono-synth-redis` |
| `jaeger` | `chrono-synth-jaeger` |
| `redpanda` | `chrono-synth-redpanda` |
| `worker` / `observability-worker` | `chrono-synth-observability-worker` |
| `prometheus` | `chrono-synth-prometheus` |
| `grafana` | `chrono-synth-grafana` |

## 3. 默认容器、网络与卷

### 3.1 网络

默认 network：

```text
chrono-synth-podman
```

### 3.2 卷

默认 volumes：

- `chrono-synth-pg-data`
- `chrono-synth-redis-data`
- `chrono-synth-redpanda-data`
- `chrono-synth-prometheus-data`
- `chrono-synth-grafana-data`

### 3.3 端口

| 宿主机端口 | 容器 | 用途 |
| --- | --- | --- |
| `8088` | frontend:8080 | Web 入口与所有反向代理 |
| `3100` | backend:3000 | 直接访问后端 |
| `16686` | jaeger:16686 | Jaeger UI |
| `4319` | jaeger:4318 | OTLP HTTP 入口 |

## 4. 环境变量参考

以下变量可通过 shell 环境或 `podman/.env` 覆盖。

### 4.1 构建与镜像

| 变量 | 默认值 | 用途 |
| --- | --- | --- |
| `ENGINE` | `podman` | 容器引擎命令名 |
| `REGISTRY` | `ghcr.io/wontlost-ltd` | 镜像名前缀 |
| `TAG` | `latest` | 镜像 tag |
| `BACKEND_SRC` | `../chrono-synth-os` | 后端源码目录 |
| `FRONTEND_SRC` | `../chrono-synth-web` | 前端源码目录 |
| `BACKEND_IMAGE` | `${REGISTRY}/chrono-synth-os:${TAG}` | 运行时后端镜像 |
| `FRONTEND_IMAGE` | `${REGISTRY}/chrono-synth-web:${TAG}` | 运行时前端镜像 |
| `PODMAN_SKIP_BUILD` | `false` | `up` 时跳过镜像构建 |

### 4.2 本地端口与公共入口

| 变量 | 默认值 | 用途 |
| --- | --- | --- |
| `BACKEND_PORT` | `3100` | 后端映射端口 |
| `FRONTEND_PORT` | `8088` | 前端映射端口 |
| `JAEGER_PORT` | `16686` | Jaeger UI 端口 |
| `OTEL_PORT` | `4319` | OTLP HTTP 端口 |
| `SERVER_PUBLIC_URL` | `http://localhost:${FRONTEND_PORT}` | OIDC / SSO / 浏览器公共访问地址 |

### 4.3 应用层配置

| 变量 | 默认值 | 用途 |
| --- | --- | --- |
| `PG_PASSWORD` | `chrono_dev` | PostgreSQL 密码 |
| `JWT_ENABLED` | `true` | 启用 JWT |
| `JWT_SECRET` | `local-dev-jwt-secret-not-for-production` | JWT 密钥 |
| `METRICS_SCRAPE_KEY` | `local-dev-metrics-scrape-key` | Prometheus 抓取 `/metrics/prometheus` 的 Bearer token |
| `ENCRYPTION_MASTER_KEY` | `MDEyMzQ1Njc4OWFiY2RlZjAxMjM0NTY3ODlhYmNkZWY=` | 本地加密主密钥，必须是解码后 32 字节的 base64 |
| `ENCRYPTION_KEYRING_JSON` | `{"tenant_e2e_key":"..."}` | 本地企业控制面 `tenant_dedicated` keyring；值必须是合法 JSON |
| `ENTERPRISE_E2E_KMS_KEY_REF` | `tenant_e2e_key` | E2E 脚本写入 deployment profile 时使用的租户 key ref |
| `LOG_LEVEL` | `info` | 日志级别 |
| `OTEL_ENABLED` | `true` | 启用 OTEL |
| `INTELLIGENCE_PROVIDER` | `openai` | 智能提供方 |
| `INTELLIGENCE_API_KEY` | 空 | LLM API key |
| `INTELLIGENCE_BASE_URL` | `https://right.codes/codex/v1` | LLM base URL |
| `INTELLIGENCE_MODEL` | `gpt-5.2` | 默认模型 |
| `STRIPE_ENABLED` | `false` | 启用 Stripe |
| `STRIPE_SECRET_KEY` | 空 | Stripe secret key |
| `STRIPE_PUBLISHABLE_KEY` | 空 | Stripe publishable key |
| `STRIPE_WEBHOOK_SECRET` | 空 | Stripe webhook secret |
| `WEB_ENVIRONMENT` | `podman` | frontend runtime `environment` 注入值 |
| `WEB_API_BASE_URL` | 空 | frontend runtime `apiBaseUrl`，默认走同源代理 |
| `WEB_SENTRY_DSN` | 空 | frontend runtime `sentryDsn` |

### 4.4 观测组件镜像

| 变量 | 默认值 | 用途 |
| --- | --- | --- |
| `REDPANDA_IMAGE` | `docker.redpanda.com/redpandadata/redpanda:v25.3.10` | Kafka 兼容 broker 镜像，固定到当前脚本验证过的官方版本 |
| `REDPANDA_BOOTSTRAP_TOPICS` | `observability.events tenant-e2e.observability.events` | `up` 时预创建的 topic 列表，保证本地 E2E 中 worker 启动后即可订阅租户观测 topic |
| `PROMETHEUS_IMAGE` | `prom/prometheus:latest` | Prometheus 镜像 |
| `GRAFANA_IMAGE` | `grafana/grafana:latest` | Grafana 镜像 |
| `GRAFANA_ADMIN_USER` | `admin` | Grafana 管理员用户名 |
| `GRAFANA_ADMIN_PASSWORD` | `admin` | Grafana 管理员密码 |

### 4.5 Podman 资源命名

| 变量 | 默认值 | 用途 |
| --- | --- | --- |
| `PODMAN_NETWORK_NAME` | `chrono-synth-podman` | 本地网络名 |
| `PODMAN_PG_VOLUME` | `chrono-synth-pg-data` | PostgreSQL 数据卷 |
| `PODMAN_REDIS_VOLUME` | `chrono-synth-redis-data` | Redis 数据卷 |
| `PODMAN_REDPANDA_VOLUME` | `chrono-synth-redpanda-data` | Redpanda 数据卷 |
| `PODMAN_PROMETHEUS_VOLUME` | `chrono-synth-prometheus-data` | Prometheus 数据卷 |
| `PODMAN_GRAFANA_VOLUME` | `chrono-synth-grafana-data` | Grafana 数据卷 |

## 5. 手工核验的关键地址

| 地址 | 说明 |
| --- | --- |
| `http://localhost:8088/` | 前端首页 |
| `http://localhost:8088/enterprise` | 企业控制台 |
| `http://localhost:8088/persona-core` | Persona Core 页面 |
| `http://localhost:8088/marketplace` | Marketplace 页面 |
| `http://localhost:3100/healthz` | 后端健康检查 |
| `http://localhost:3100/readyz` | 后端就绪检查 |
| `http://localhost:8088/worker/healthz` | Worker 健康检查 |
| `http://localhost:8088/worker/readyz` | Worker 就绪检查 |
| `http://localhost:8088/worker/metrics` | Worker 指标 |
| `http://localhost:8088/prometheus/targets` | Prometheus targets 页面 |
| `http://localhost:8088/grafana/api/health` | Grafana 健康 API |
| `http://localhost:8088/grafana/d/chrono-synth-overview/chrono-synth-enterprise-overview` | Grafana 仪表盘 |
| `http://localhost:16686/` | Jaeger UI |

## 6. 常见问题与处理

### 6.1 `podman info` 失败

现象：

- `deploy.sh podman up` 很快退出
- 报错提示无法连接 Podman

处理：

```bash
podman machine start
podman info
```

若你不使用 Podman Machine，则确认 rootless/rootful Podman 服务可用。

### 6.2 镜像构建失败

优先检查：

1. `../chrono-synth-os` 与 `../chrono-synth-web` 是否存在。
2. `BACKEND_SRC` / `FRONTEND_SRC` 是否被错误覆盖。
3. 容器构建时是否能拉取基础镜像。

建议命令：

```bash
./deploy.sh podman build
podman images | grep chrono-synth
```

### 6.3 后端容器启动失败

建议按顺序排查：

```bash
./deploy.sh podman logs postgres
./deploy.sh podman logs redis
./deploy.sh podman logs backend
podman inspect --format '{{.State.Status}} {{if .State.Health}}{{.State.Health.Status}}{{else}}no-health{{end}}' chrono-synth-backend
```

重点看：

- PostgreSQL 是否 ready
- `CHRONO_DB_CONNECTION_STRING` 是否可连
- 后端 migration / startup log 是否报错

### 6.4 Worker 未进入 Kafka 模式

症状：

- `worker/metrics` 中看不到 `chrono_observability_worker_mode{mode="kafka"} 1`

排查：

```bash
./deploy.sh podman logs redpanda
./deploy.sh podman logs worker
podman exec chrono-synth-redpanda rpk cluster health -X admin.hosts=127.0.0.1:9644
curl http://localhost:8088/worker/metrics | grep chrono_observability_worker_mode
```

重点看：

- Redpanda Admin API 是否 healthy
- `REDPANDA_BOOTSTRAP_TOPICS` 是否包含 `observability.events` 与对应租户 topic，例如 `tenant-e2e.observability.events`
- worker 是否出现 Kafka 连接失败并回退到 direct 模式

### 6.5 Prometheus 抓取 backend metrics 失败

症状：

- `http://localhost:8088/prometheus/targets` 中 backend target 为 `down`
- backend `/metrics/prometheus` 手动带 JWT 可以访问，但 Prometheus 没有样本

优先检查：

```bash
cat podman/.env | grep METRICS_SCRAPE_KEY
podman exec chrono-synth-prometheus cat /run/secrets/metrics-scrape-token
podman logs chrono-synth-prometheus
```

确认点：

- `METRICS_SCRAPE_KEY` 非空
- Podman 已把 token 挂载到 `/run/secrets/metrics-scrape-token`
- backend 使用同一个 `CHRONO_AUTH_METRICS_API_KEYS`

### 6.6 `masterKey 解码后必须为 32 字节`

症状：

- backend 启动即退出
- 日志包含 `masterKey 解码后必须为 32 字节`

处理：

```bash
openssl rand -base64 32
```

把输出写入 `podman/.env` 的 `ENCRYPTION_MASTER_KEY=`。若要跑企业控制面 `tenant_dedicated` 场景，还需要同时写入与 `ENTERPRISE_E2E_KMS_KEY_REF` 对应的 `ENCRYPTION_KEYRING_JSON=`。也可以直接执行：

```bash
./deploy.sh secrets
```

### 6.7 前端代理失败

症状：

- `/worker/healthz`、`/prometheus/-/healthy`、`/grafana/api/health` 返回 404/502

排查：

```bash
./deploy.sh podman logs frontend
podman inspect --format '{{range .NetworkSettings.Networks}}{{.IPAddress}} {{.Aliases}}{{end}}' chrono-synth-backend
podman inspect --format '{{range .NetworkSettings.Networks}}{{.IPAddress}} {{.Aliases}}{{end}}' chrono-synth-observability-worker
podman inspect --format '{{range .NetworkSettings.Networks}}{{.IPAddress}} {{.Aliases}}{{end}}' chrono-synth-prometheus
podman inspect --format '{{range .NetworkSettings.Networks}}{{.IPAddress}} {{.Aliases}}{{end}}' chrono-synth-grafana
```

确认网络别名分别存在：

- backend
- observability-worker
- prometheus
- grafana

### 6.8 数据脏导致测试不稳定

症状：

- 第二次执行 E2E 出现冲突、历史租户数据影响测试

处理：

```bash
./deploy.sh podman down
podman volume rm \
  chrono-synth-pg-data \
  chrono-synth-redis-data \
  chrono-synth-redpanda-data \
  chrono-synth-prometheus-data \
  chrono-synth-grafana-data
```

然后重新执行：

```bash
./deploy.sh podman build
./deploy.sh podman up
./scripts/e2e-test.sh
```

## 7. 推荐排障顺序

遇到故障时，按下面顺序最省时间：

1. `podman info`
2. `podman ps -a`
3. `./scripts/health-check.sh http://localhost:8088`
4. `./deploy.sh podman logs backend`
5. `./deploy.sh podman logs worker`
6. `./deploy.sh podman logs frontend`
7. `./scripts/e2e-test.sh`

## 8. 文档关系

- 手工执行步骤看 [podman-manual-test.md](podman-manual-test.md)
- 总入口和拓扑概览看 [../README.md](../README.md)

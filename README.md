# ChronoSynth Deploy

ChronoSynth 的统一部署与编排仓库，负责把 `chrono-synth-os`、`chrono-synth-web` 以及企业级运行面能力组装成可运行的交付拓扑。

当前仓库覆盖三类能力，并且本地运行完全基于原生 `podman` CLI 脚本，不依赖任何 Compose 兼容层：

- 应用面：前端控制台、后端 API、PostgreSQL、Redis。
- 企业面：OIDC / SCIM 所需的公共入口、Organizations / RBAC、Audit 查询与控制台代理。
- 观测面：独立 `observability-worker`、Kafka 兼容 broker、Prometheus、Grafana、Jaeger。

## 文档导航

- [docs/production-readiness.md](docs/production-readiness.md)
  面向生产评审的基线结论、Hard Gates、残余上线项与发布要求。
- [docs/podman-manual-test.md](docs/podman-manual-test.md)
  面向手工脚本测试的标准操作手册，覆盖准备、构建、启动、验证、日志、清理。
- [docs/podman-reference.md](docs/podman-reference.md)
  原生 Podman 脚本参数、环境变量、容器拓扑、常见问题和排障命令总表。

## 快速开始

### 本地 Podman 企业闭环

```bash
cp podman/.env.example podman/.env
./deploy.sh podman build
./deploy.sh podman up

# 前端控制台
# http://localhost:8088
# http://localhost:8088/enterprise
#
# Persona Core / Marketplace
# http://localhost:8088/persona-core
# http://localhost:8088/marketplace
#
# 观测代理
# http://localhost:8088/worker/healthz
# http://localhost:8088/prometheus/targets
# http://localhost:8088/grafana/d/chrono-synth-overview/chrono-synth-enterprise-overview
#
# 追踪
# http://localhost:16686

./scripts/e2e-test.sh
./deploy.sh podman down
```

K8s 清单评审前建议先跑：

```bash
./scripts/validate-k8s.sh
```

如果你准备按文档手工逐步验证，而不是直接一把跑完，建议按下面顺序：

1. 阅读 [docs/podman-manual-test.md](docs/podman-manual-test.md) 的“准备环境”和“标准测试流程”。
2. 按 [podman/.env.example](podman/.env.example) 生成并调整 `podman/.env`。
3. 执行 `./deploy.sh podman build`、`./deploy.sh podman up`。
4. 执行 `./scripts/health-check.sh http://localhost:8088` 与 `./scripts/e2e-test.sh`。
5. 如果失败，查 [docs/podman-reference.md](docs/podman-reference.md) 的日志与排障章节。

### K3s 集群部署

```bash
./deploy.sh secrets
./deploy.sh build --push
./deploy.sh k3s dev
./deploy.sh status
```

## 本地 Podman 拓扑

| 服务 | 容器名 | 作用 | 关键入口 |
| --- | --- | --- | --- |
| Frontend | `chrono-synth-frontend` | 单一 Web 入口，代理 `/api/`、`/worker/`、`/prometheus/`、`/grafana/` | `http://localhost:8088/` |
| Backend | `chrono-synth-backend` | 主 API 进程，关闭内置 worker，启用 Kafka 观测管线 | `http://localhost:3100/healthz` |
| Worker | `chrono-synth-observability-worker` | 独立消费观测事件并暴露健康/指标接口 | `http://localhost:8088/worker/healthz` |
| PostgreSQL | `chrono-synth-postgres` | 主业务数据库 | 容器内 `postgres:5432` |
| Redis | `chrono-synth-redis` | 队列与缓存依赖 | 容器内 `redis:6379` |
| Redpanda | `chrono-synth-redpanda` | Kafka 兼容 broker | 容器内 `redpanda:9092` |
| Prometheus | `chrono-synth-prometheus` | 抓取后端与 worker 指标 | `http://localhost:8088/prometheus/targets` |
| Grafana | `chrono-synth-grafana` | 预置企业级仪表盘 | `http://localhost:8088/grafana/` |
| Jaeger | `chrono-synth-jaeger` | OTLP 接收与追踪 UI | `http://localhost:16686/` |

## 原生 Podman 脚本入口

| 命令 | 作用 |
| --- | --- |
| `./deploy.sh podman build` | 构建 `chrono-synth-os` 与 `chrono-synth-web` 镜像 |
| `./deploy.sh podman up` | 创建 network / volume，并按依赖顺序启动全部容器 |
| `./deploy.sh podman logs backend` | 跟随后端日志，`backend` 可替换成 `worker`、`frontend`、`postgres`、`redis`、`redpanda`、`prometheus`、`grafana`、`jaeger` |
| `./deploy.sh podman down` | 停止并删除全部容器与网络，保留卷数据 |
| `./scripts/health-check.sh http://localhost:8088` | 验证前端代理、后端、worker、Prometheus、Grafana 健康 |
| `./scripts/e2e-test.sh` | 执行全链路脚本测试 |

## 本地 E2E 覆盖

`scripts/e2e-test.sh` 现在验证以下闭环：

- 容器状态与代理健康检查。
- 注册 / 登录，获取管理员 JWT。
- 更新 tenant deployment profile。
- 生成 SCIM token，并通过 `/scim/v2/Users` 创建企业成员。
- 创建 organization 并把成员绑定到 organization roles。
- 查询 audit logs。
- 走 Persona Core / Marketplace / Avatar / Autorun 主链路。
- 校验 worker / Prometheus / Grafana 代理与观测指标。

## K8s 基础能力

`k8s/base` 已补齐以下资源：

- 独立 `observability-worker` Deployment / Service。
- Prometheus Deployment / Service + ConfigMap。
- Grafana Deployment / Service + ConfigMap provisioning。
- 前端 Nginx 子路径代理 `/worker/`、`/prometheus/`、`/grafana/`。
- frontend runtime config ConfigMap，支持 `chrono-synth-web` 的运行时环境注入。
- metrics scrape token Secret，Prometheus 通过 Bearer token 抓取 `/metrics/prometheus`。

当前 `k8s/base` 默认采用独立 worker 模式，不内建 Kafka 集群。生产环境建议在 overlay 中接入外部 Kafka / Redpanda / Strimzi，再把 `CHRONO_OBSERVABILITY_KAFKA_ENABLED=true` 打开。

`k8s/overlays/staging` 与 `k8s/overlays/prod` 现在默认开启：

- `CHRONO_AUTH_ENABLED=true`
- `CHRONO_AUTH_REQUIRE_DB_KEYS=true`
- `CHRONO_ENCRYPTION_ENABLED=true`
- frontend 非 root + `8080` 容器端口
- Prometheus 带 token 抓取 metrics
- prod `PodDisruptionBudget`

## 项目结构

```text
chrono-synth-deploy/
├── deploy.sh
├── README.md
├── prometheus-scrape-jobs.yml.tpl  # 共享 scrape job 模板（podman/k8s 差异对照表）
├── docs/
│   ├── production-readiness.md
│   ├── podman-manual-test.md
│   └── podman-reference.md
├── k8s/
│   ├── base/
│   │   ├── backend/
│   │   ├── frontend/
│   │   ├── observability-worker/
│   │   ├── prometheus/
│   │   │   └── prometheus.yml      # 引用 ../../prometheus-scrape-jobs.yml.tpl
│   │   ├── grafana/
│   │   ├── postgres/
│   │   ├── redis/
│   │   ├── jaeger/
│   │   ├── ingress.yaml
│   │   ├── kustomization.yaml
│   │   ├── namespace.yaml
│   │   └── network-policy.yaml
│   └── overlays/
│       ├── dev/
│       ├── staging/
│       └── prod/
├── podman/
│   ├── .env.example
│   └── prometheus/
│       └── prometheus.yml          # 引用 ../../prometheus-scrape-jobs.yml.tpl
└── scripts/
    ├── build-images.sh
    ├── e2e-test.sh
    ├── generate-secrets.sh
    ├── health-check.sh
    ├── import-k3s.sh
    ├── podman-native.sh
    ├── push-images.sh
    └── validate-k8s.sh
```

## 关键配置

- `SERVER_PUBLIC_URL`
  必须设置为用户访问前端控制台的地址，例如 `http://localhost:8088`。OIDC callback、SSO 跳转和企业入口都依赖这个地址。
- `BACKEND_PORT` / `FRONTEND_PORT` / `JAEGER_PORT`
  本地端口映射入口。若调整端口，手工验证、`health-check.sh`、`e2e-test.sh` 也应同步传参或读取同一份 `.env`。
- `GRAFANA_ADMIN_USER` / `GRAFANA_ADMIN_PASSWORD`
  Grafana 管理员账号，本地默认值可直接使用。
- `METRICS_SCRAPE_KEY` / `ENCRYPTION_MASTER_KEY` / `ENCRYPTION_KEYRING_JSON`
  本地 Podman 现在会用这些值分别完成 Prometheus metrics 抓取、主加密基线初始化，以及企业控制面 `tenant_dedicated` keyring 注入。
- `INTELLIGENCE_API_KEY`
  若你要手测 Avatar Autorun 与 LLM 知识源能力，建议在本地填入可用值，否则相关链路可能只验证到入队/配置阶段。
- `STRIPE_*`
  本地默认关闭；启用时仍建议沿用前端公共地址作为 `SERVER_PUBLIC_URL`。
- `PODMAN_SKIP_BUILD` / `BACKEND_IMAGE` / `FRONTEND_IMAGE`
  可用于复用预构建镜像，详见 [docs/podman-reference.md](docs/podman-reference.md)。

## 前置要求

- `podman` >= 4.0
- 需要可用的 Podman daemon / machine（例如 `podman machine start`）
- 建议同时具备 `curl`、`jq`、`openssl`
- `kubectl` + k3s 集群访问
- 同级源码目录：`../chrono-synth-os/` 与 `../chrono-synth-web/`

## 验证建议

1. `./deploy.sh podman build`
2. `./deploy.sh podman up`
3. `./scripts/e2e-test.sh`
4. 登录 `http://localhost:8088/enterprise`
5. 检查 `/worker/healthz`、`/prometheus/targets`、`/grafana/...`
6. `./deploy.sh podman down`

如果要做完整人工回归，请直接按照 [docs/podman-manual-test.md](docs/podman-manual-test.md) 的步骤执行。

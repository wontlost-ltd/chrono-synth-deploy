# Deploy Production Readiness

## Verdict

`chrono-synth-deploy` 现在具备可直接进入企业生产评审的交付基线，但前提是：

1. 生产环境使用 `k8s/overlays/prod`
2. 注入真实 `Secret`，尤其是：
   - `backend-secrets`
   - `prometheus-scrape-auth`
   - PostgreSQL / Kafka / Intelligence provider 凭据
   - `CHRONO_ENCRYPTION_MASTER_KEY` 必须使用 `openssl rand -base64 32` 生成
   - 若启用企业租户 `tenant_dedicated` 加密，必须同步提供 `CHRONO_ENCRYPTION_KEYRING_JSON`
3. 外接真实 PostgreSQL / Redis / Kafka，而不是示例内嵌依赖
4. 发布前执行 `validate-k8s + smoke + Podman E2E + 预发演练`

如果这 4 个前提满足，我认为 `chrono-synth-deploy` 已达到企业生产部署仓库的基线要求。

## Hard Gates

- `bash -n deploy.sh scripts/*.sh`
- `./scripts/validate-k8s.sh`
- `chrono-synth-os` CI 绿色
- `chrono-synth-web` CI 绿色
- 本地 `./deploy.sh podman up`
- 本地 `./scripts/e2e-test.sh`
- 生产环境必须满足：
  - `CHRONO_AUTH_ENABLED=true`
  - `CHRONO_AUTH_REQUIRE_DB_KEYS=true`
  - `CHRONO_JWT_ENABLED=true`
  - `CHRONO_ENCRYPTION_ENABLED=true`
  - 使用 `tenant_dedicated` 前必须保证 `CHRONO_ENCRYPTION_KEYRING_JSON` 中存在对应 `kmsKeyRef`
  - `CHRONO_SERVER_PUBLIC_URL=https://<your-domain>`
  - `Prometheus -> /metrics/prometheus` 使用 Bearer token
  - frontend 以非 root 运行

## What Changed

- `chrono-synth-web` 运行时配置通过 K8s ConfigMap / Podman env 注入，不再要求按环境重建镜像。
- K8s frontend Deployment 对齐到非 root Nginx 镜像和 `8080` 容器端口。
- backend 基线默认开启 auth / DB key enforcement / encryption。
- Prometheus 抓取 backend metrics 现在通过 `prometheus-scrape-auth` Bearer token。
- `staging` / `prod` overlay 显式开启 secure defaults。
- `prod` 增加 backend / frontend / worker `PodDisruptionBudget`。
- 新增 `validate-k8s.sh` 和 CI 工作流，保证清单不是“能 apply 就算完”。

## Remaining Operational Work

- 用托管 PostgreSQL / Redis / Kafka 替换示例依赖，并完成容量参数调优。
- 把 `backend-secrets`、`prometheus-scrape-auth` 接入 Vault / KMS / External Secrets。
- 配置真实 TLS、WAF、Ingress policy、证书轮换。
- 在预发做一次回滚演练与观测链路故障演练。
- 根据租户流量校准 HPA、Prometheus retention、Grafana 告警阈值。

## Recommended Release Flow

1. 在 `chrono-synth-os` 与 `chrono-synth-web` 仓库分别跑完 CI gates。
2. 在本仓库执行 `./scripts/validate-k8s.sh`。
3. 用 `./deploy.sh podman up` + `./scripts/e2e-test.sh` 做本地全链路回归。
4. 在预发集群应用 `k8s/overlays/staging`。
5. 注入真实 staging secrets，确认 Prometheus/Grafana/Jaeger 可用。
6. 预发通过后，再发布 `k8s/overlays/prod` 并小流量灰度。

# ChronoSynth Deploy

ChronoSynth 统一部署项目 — 管理 [chrono-synth-os](https://github.com/rpang/chrono-synth-os)（后端）和 [chrono-synth-web](https://github.com/rpang/chrono-synth-web)（前端）的容器构建、配置与编排。

## 快速开始

### 本地 Podman 测试

```bash
# 1. 准备环境配置
cp podman/.env.example podman/.env

# 2. 一键启动（构建 + 运行）
./deploy.sh podman up

# 3. 访问
# 前端: http://localhost:80
# 后端: http://localhost:3000
# Jaeger: http://localhost:16686

# 4. 停止
./deploy.sh podman down
```

### K3s 集群部署

```bash
# 1. 生成安全密钥
./deploy.sh secrets

# 2. 构建并推送镜像
./deploy.sh build --push

# 3. 部署（选择环境）
./deploy.sh k3s dev       # 开发环境
./deploy.sh k3s staging   # 预发布
./deploy.sh k3s prod      # 生产环境

# 4. 查看状态
./deploy.sh status
```

## 项目结构

```
chrono-synth-deploy/
├── deploy.sh                    # 一键部署入口
├── Makefile                     # 快捷命令
├── k8s/
│   ├── base/                    # Kustomize 基础配置
│   │   ├── kustomization.yaml
│   │   ├── namespace.yaml
│   │   ├── backend/             # 后端 Deployment + Service + ConfigMap + Secret
│   │   ├── frontend/            # 前端 Deployment + Service + Nginx ConfigMap
│   │   ├── postgres/            # PostgreSQL StatefulSet + Service + Secret
│   │   ├── redis/               # Redis StatefulSet + Service
│   │   ├── jaeger/              # Jaeger Deployment + Service
│   │   ├── ingress.yaml         # Traefik Ingress
│   │   └── network-policy.yaml  # 网络策略
│   └── overlays/                # 环境差异化配置
│       ├── dev/                 # 开发：单副本、debug 日志、mock LLM
│       ├── staging/             # 预发布：生产拓扑、小规模
│       └── prod/                # 生产：HPA、TLS、严格 CORS
├── podman/
│   ├── podman-compose.yml       # 本地 5 服务全栈
│   └── .env.example             # 环境变量模板
└── scripts/
    ├── build-images.sh          # 构建后端 + 前端镜像
    ├── push-images.sh           # 推送到 GHCR
    ├── import-k3s.sh            # 导入镜像到 k3s（无 registry 模式）
    ├── generate-secrets.sh      # 生成 JWT/DB 密钥
    └── health-check.sh          # 部署后健康验证
```

## 环境差异

| 配置项 | dev | staging | prod |
|--------|-----|---------|------|
| 后端副本 | 1 | 1 | 2 (HPA 2-5) |
| 前端副本 | 1 | 1 | 2 |
| 日志级别 | debug | info | warn |
| CORS | 全开 | 关闭 | 指定域名 |
| 认证 | 关闭 | JWT | JWT + Auth |
| OTEL | 开启 | 开启 | 开启 |
| LLM | mock | 可配置 | 配置 |
| TLS | 无 | 无 | 启用 |
| PG 存储 | 5Gi | 5Gi | 20Gi |

## 依赖服务

| 服务 | 镜像 | 端口 | 用途 |
|------|------|------|------|
| PostgreSQL | postgres:17-alpine | 5432 | 主数据库 |
| Redis | redis:7-alpine | 6379 | 缓存/队列 |
| Jaeger | jaegertracing/all-in-one:1.76.0 | 16686/4318 | 分布式追踪 |

## K3s 注意事项

- **Ingress Controller**：k3s 默认使用 Traefik，IngressClass 已设为 `traefik`
- **存储**：默认 local-path provisioner（RWO），生产建议安装 Longhorn
- **NetworkPolicy**：默认 flannel CNI 不支持，需换 Calico/Cilium 才生效
- **镜像加载**：无 registry 时使用 `scripts/import-k3s.sh` 通过 `k3s ctr images import` 加载
- **metrics-server**：HPA 依赖 metrics-server，k3s 默认已包含

## Makefile 命令

```bash
make help          # 显示所有命令
make build         # 构建镜像
make push          # 推送到 GHCR
make k3s-dev       # 部署到 dev
make k3s-prod      # 部署到 prod
make podman-up     # 启动本地环境
make podman-down   # 停止本地环境
make status        # 查看状态
make secrets       # 生成密钥
make render ENV=prod  # 预览 Kustomize 渲染
```

## 前置要求

- **podman** >= 4.0 + **podman-compose** >= 1.0（本地测试）
- **kubectl** + k3s 集群访问（K8s 部署）
- **openssl**（密钥生成）
- 源码目录与本项目同级：`../chrono-synth-os/` 和 `../chrono-synth-web/`

#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ACTION="${1:-up}"
TARGET_SERVICE="${2:-}"

ENGINE="${ENGINE:-podman}"
REGISTRY="${REGISTRY:-ghcr.io/wontlost-ltd}"
TAG="${TAG:-latest}"

ENV_FILE="${ENV_FILE:-$PROJECT_ROOT/podman/.env}"
ENV_EXAMPLE="$PROJECT_ROOT/podman/.env.example"

NETWORK_NAME="${PODMAN_NETWORK_NAME:-chrono-synth-podman}"
PG_VOLUME="${PODMAN_PG_VOLUME:-chrono-synth-pg-data}"
REDIS_VOLUME="${PODMAN_REDIS_VOLUME:-chrono-synth-redis-data}"
REDPANDA_VOLUME="${PODMAN_REDPANDA_VOLUME:-chrono-synth-redpanda-data}"
PROMETHEUS_VOLUME="${PODMAN_PROMETHEUS_VOLUME:-chrono-synth-prometheus-data}"
GRAFANA_VOLUME="${PODMAN_GRAFANA_VOLUME:-chrono-synth-grafana-data}"
RUNTIME_DIR="${PODMAN_RUNTIME_DIR:-$PROJECT_ROOT/podman/.runtime}"

BACKEND_CONTAINER="chrono-synth-backend"
FRONTEND_CONTAINER="chrono-synth-frontend"
POSTGRES_CONTAINER="chrono-synth-postgres"
REDIS_CONTAINER="chrono-synth-redis"
JAEGER_CONTAINER="chrono-synth-jaeger"
REDPANDA_CONTAINER="chrono-synth-redpanda"
WORKER_CONTAINER="chrono-synth-observability-worker"
PROMETHEUS_CONTAINER="chrono-synth-prometheus"
GRAFANA_CONTAINER="chrono-synth-grafana"

CONTAINERS=(
  "$FRONTEND_CONTAINER"
  "$GRAFANA_CONTAINER"
  "$PROMETHEUS_CONTAINER"
  "$WORKER_CONTAINER"
  "$BACKEND_CONTAINER"
  "$JAEGER_CONTAINER"
  "$REDPANDA_CONTAINER"
  "$REDIS_CONTAINER"
  "$POSTGRES_CONTAINER"
)

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
title() { echo -e "\n${BLUE}=== $1 ===${NC}\n"; }

ensure_env_file() {
  if [ -f "$ENV_FILE" ]; then
    return
  fi

  warn ".env 文件不存在，从模板创建..."
  cp "$ENV_EXAMPLE" "$ENV_FILE"
  info "已创建 $ENV_FILE，请根据需要修改配置"
}

load_env() {
  ensure_env_file
  set -a
  # shellcheck disable=SC1090
  . "$ENV_FILE"
  set +a

  : "${BACKEND_PORT:=3100}"
  : "${FRONTEND_PORT:=8088}"
  : "${JAEGER_PORT:=16686}"
  : "${OTEL_PORT:=4319}"
  : "${PG_PASSWORD:=chrono_dev}"
  : "${JWT_ENABLED:=true}"
  : "${JWT_SECRET:=local-dev-jwt-secret-not-for-production}"
  : "${METRICS_SCRAPE_KEY:=local-dev-metrics-scrape-key}"
  : "${ENCRYPTION_MASTER_KEY:=MDEyMzQ1Njc4OWFiY2RlZjAxMjM0NTY3ODlhYmNkZWY=}"
  : "${ENCRYPTION_KEYRING_JSON:=}"
  : "${ENTERPRISE_E2E_KMS_KEY_REF:=tenant_e2e_key}"
  if [ -z "$ENCRYPTION_KEYRING_JSON" ]; then
    ENCRYPTION_KEYRING_JSON="{\"${ENTERPRISE_E2E_KMS_KEY_REF}\":\"ZmVkY2JhOTg3NjU0MzIxMGZlZGNiYTk4NzY1NDMyMTA=\"}"
  fi
  : "${LOG_LEVEL:=info}"
  : "${OTEL_ENABLED:=true}"
  : "${INTELLIGENCE_PROVIDER:=openai}"
  : "${INTELLIGENCE_API_KEY:=}"
  : "${INTELLIGENCE_BASE_URL:=https://right.codes/codex/v1}"
  : "${INTELLIGENCE_MODEL:=gpt-5.2}"
  : "${STRIPE_ENABLED:=false}"
  : "${STRIPE_SECRET_KEY:=}"
  : "${STRIPE_PUBLISHABLE_KEY:=}"
  : "${STRIPE_WEBHOOK_SECRET:=}"
  : "${SERVER_PUBLIC_URL:=http://localhost:${FRONTEND_PORT}}"
  : "${WEB_ENVIRONMENT:=podman}"
  : "${WEB_API_BASE_URL:=}"
  : "${WEB_SENTRY_DSN:=}"
  : "${GRAFANA_ADMIN_USER:=admin}"
  : "${GRAFANA_ADMIN_PASSWORD:=admin}"
  : "${REDPANDA_IMAGE:=docker.redpanda.com/redpandadata/redpanda:v25.3.10}"
  : "${REDPANDA_BOOTSTRAP_TOPICS:=observability.events tenant-e2e.observability.events}"
  : "${PROMETHEUS_IMAGE:=prom/prometheus:latest}"
  : "${GRAFANA_IMAGE:=grafana/grafana:latest}"
  # 后端启动会执行 CREATE EXTENSION vector（DSL 迁移），必须用 pgvector 镜像而非裸 postgres
  : "${POSTGRES_IMAGE:=docker.io/pgvector/pgvector:pg17}"
}

require_podman() {
  if ! command -v "$ENGINE" >/dev/null 2>&1; then
    error "未找到容器引擎: $ENGINE"
    exit 1
  fi

  if ! "$ENGINE" info --format '{{.Version.Version}}' >/dev/null 2>&1; then
    error "无法连接到 Podman。请先确认 podman machine 已启动，或执行 'podman machine start'。"
    exit 1
  fi
}

container_exists() {
  "$ENGINE" container exists "$1" >/dev/null 2>&1
}

remove_container_if_exists() {
  local name="$1"
  if container_exists "$name"; then
    "$ENGINE" rm -f "$name" >/dev/null
  fi
}

ensure_network() {
  if ! "$ENGINE" network exists "$NETWORK_NAME" >/dev/null 2>&1; then
    info "创建网络: $NETWORK_NAME"
    "$ENGINE" network create "$NETWORK_NAME" >/dev/null
  fi
}

ensure_volume() {
  local name="$1"
  if ! "$ENGINE" volume exists "$name" >/dev/null 2>&1; then
    info "创建数据卷: $name"
    "$ENGINE" volume create "$name" >/dev/null
  fi
}

ensure_runtime_dir() {
  mkdir -p "$RUNTIME_DIR"
  chmod 700 "$RUNTIME_DIR"
}

wait_for_container_health() {
  local name="$1"
  local timeout_seconds="${2:-180}"
  local deadline=$((SECONDS + timeout_seconds))

  while [ "$SECONDS" -lt "$deadline" ]; do
    local state
    state="$("$ENGINE" inspect --format '{{.State.Status}} {{if .State.Health}}{{.State.Health.Status}}{{else}}no-health{{end}}' "$name" 2>/dev/null || echo "missing")"
    case "$state" in
      "running healthy"|\
      "running no-health")
        info "$name 已就绪 ($state)"
        return 0
        ;;
      "created "*|"configured "*|"running starting")
        sleep 2
        ;;
      "exited "*|"stopped "*|"missing")
        error "$name 未成功启动 ($state)"
        "$ENGINE" logs "$name" 2>/dev/null || true
        return 1
        ;;
      *"unhealthy"*)
        error "$name 健康检查失败 ($state)"
        "$ENGINE" logs "$name" 2>/dev/null || true
        return 1
        ;;
      *)
        sleep 2
        ;;
    esac
  done

  error "$name 在 ${timeout_seconds}s 内未就绪"
  "$ENGINE" logs "$name" 2>/dev/null || true
  return 1
}

wait_for_http_ready() {
  local label="$1"
  local url="$2"
  local timeout_seconds="${3:-120}"
  local deadline=$((SECONDS + timeout_seconds))

  while [ "$SECONDS" -lt "$deadline" ]; do
    if command -v curl >/dev/null 2>&1; then
      if curl -fsS --max-time 3 "$url" >/dev/null 2>&1; then
        info "$label 已就绪 (http)"
        return 0
      fi
    elif command -v wget >/dev/null 2>&1; then
      if wget -qO- "$url" >/dev/null 2>&1; then
        info "$label 已就绪 (http)"
        return 0
      fi
    else
      error "宿主机缺少 curl/wget，无法执行 HTTP 就绪检查"
      return 1
    fi

    sleep 2
  done

  error "$label 在 ${timeout_seconds}s 内未通过 HTTP 就绪检查: $url"
  return 1
}

resolve_service_container() {
  case "$1" in
    backend|chrono-synth-backend) echo "$BACKEND_CONTAINER" ;;
    frontend|chrono-synth-frontend) echo "$FRONTEND_CONTAINER" ;;
    postgres|chrono-synth-postgres) echo "$POSTGRES_CONTAINER" ;;
    redis|chrono-synth-redis) echo "$REDIS_CONTAINER" ;;
    jaeger|chrono-synth-jaeger) echo "$JAEGER_CONTAINER" ;;
    redpanda|chrono-synth-redpanda) echo "$REDPANDA_CONTAINER" ;;
    worker|observability-worker|chrono-synth-observability-worker) echo "$WORKER_CONTAINER" ;;
    prometheus|chrono-synth-prometheus) echo "$PROMETHEUS_CONTAINER" ;;
    grafana|chrono-synth-grafana) echo "$GRAFANA_CONTAINER" ;;
    "")
      error "请指定日志服务，例如: ./deploy.sh podman logs backend"
      exit 1
      ;;
    *)
      error "未知服务: $1"
      exit 1
      ;;
  esac
}

backend_image() {
  echo "${BACKEND_IMAGE:-${REGISTRY}/chrono-synth-os:${TAG}}"
}

frontend_image() {
  echo "${FRONTEND_IMAGE:-${REGISTRY}/chrono-synth-web:${TAG}}"
}

build_images() {
  title "构建本地镜像"
  ENGINE="$ENGINE" REGISTRY="$REGISTRY" TAG="$TAG" bash "$PROJECT_ROOT/scripts/build-images.sh"
}

common_labels() {
  printf -- '--label\nchrono.stack=chrono-synth\n--label\nchrono.runtime=podman\n'
}

run_postgres() {
  remove_container_if_exists "$POSTGRES_CONTAINER"
  "$ENGINE" run -d \
    --name "$POSTGRES_CONTAINER" \
    --network "$NETWORK_NAME" \
    --network-alias postgres \
    --restart unless-stopped \
    --label chrono.stack=chrono-synth \
    --label chrono.runtime=podman \
    -e POSTGRES_DB=chrono_synth \
    -e POSTGRES_USER=chrono \
    -e POSTGRES_PASSWORD="$PG_PASSWORD" \
    -v "${PG_VOLUME}:/var/lib/postgresql/data" \
    --health-cmd "pg_isready -U chrono -d chrono_synth" \
    --health-interval 10s \
    --health-timeout 5s \
    --health-retries 5 \
    --health-start-period 10s \
    "$POSTGRES_IMAGE" >/dev/null
}

run_redis() {
  remove_container_if_exists "$REDIS_CONTAINER"
  "$ENGINE" run -d \
    --name "$REDIS_CONTAINER" \
    --network "$NETWORK_NAME" \
    --network-alias redis \
    --restart unless-stopped \
    --label chrono.stack=chrono-synth \
    --label chrono.runtime=podman \
    -v "${REDIS_VOLUME}:/data" \
    --health-cmd "redis-cli ping" \
    --health-interval 10s \
    --health-timeout 3s \
    --health-retries 5 \
    --health-start-period 5s \
    redis:7-alpine \
    redis-server --save 60 1 --loglevel warning >/dev/null
}

run_redpanda() {
  remove_container_if_exists "$REDPANDA_CONTAINER"
  "$ENGINE" run -d \
    --name "$REDPANDA_CONTAINER" \
    --network "$NETWORK_NAME" \
    --network-alias redpanda \
    --restart unless-stopped \
    --label chrono.stack=chrono-synth \
    --label chrono.runtime=podman \
    -v "${REDPANDA_VOLUME}:/var/lib/redpanda/data" \
    --health-cmd "rpk cluster health -X admin.hosts=127.0.0.1:9644 >/dev/null 2>&1" \
    --health-interval 10s \
    --health-timeout 5s \
    --health-retries 8 \
    --health-start-period 20s \
    "$REDPANDA_IMAGE" \
    redpanda start \
      --mode=dev-container \
      --overprovisioned \
      --smp=1 \
      --memory=512M \
      --reserve-memory=0M \
      --check=false \
      --node-id=0 \
      --rpc-addr=redpanda:33145 \
      --advertise-rpc-addr=redpanda:33145 \
      --kafka-addr=PLAINTEXT://0.0.0.0:9092 \
      --advertise-kafka-addr=PLAINTEXT://redpanda:9092 >/dev/null
}

bootstrap_redpanda_topics() {
  if [ -z "${REDPANDA_BOOTSTRAP_TOPICS:-}" ]; then
    return
  fi

  local topic
  for topic in $REDPANDA_BOOTSTRAP_TOPICS; do
    if [ -z "$topic" ]; then
      continue
    fi
    "$ENGINE" exec "$REDPANDA_CONTAINER" \
      rpk topic create "$topic" --brokers redpanda:9092 \
      >/dev/null 2>&1 || true
  done
}

run_jaeger() {
  remove_container_if_exists "$JAEGER_CONTAINER"
  "$ENGINE" run -d \
    --name "$JAEGER_CONTAINER" \
    --network "$NETWORK_NAME" \
    --network-alias jaeger \
    --restart unless-stopped \
    --label chrono.stack=chrono-synth \
    --label chrono.runtime=podman \
    -p "${JAEGER_PORT}:16686" \
    -p "${OTEL_PORT}:4318" \
    -e COLLECTOR_OTLP_ENABLED=true \
    --health-cmd "wget -qO- http://127.0.0.1:14269/" \
    --health-interval 10s \
    --health-timeout 3s \
    --health-retries 5 \
    --health-start-period 10s \
    jaegertracing/all-in-one:1.76.0 >/dev/null
}

run_backend() {
  remove_container_if_exists "$BACKEND_CONTAINER"
  "$ENGINE" run -d \
    --name "$BACKEND_CONTAINER" \
    --network "$NETWORK_NAME" \
    --network-alias backend \
    --restart unless-stopped \
    --label chrono.stack=chrono-synth \
    --label chrono.runtime=podman \
    -p "${BACKEND_PORT}:3000" \
    -e CHRONO_DB_DRIVER=postgres \
    -e CHRONO_DB_CONNECTION_STRING="postgresql://chrono:${PG_PASSWORD}@postgres:5432/chrono_synth" \
    -e CHRONO_LOG_LEVEL="$LOG_LEVEL" \
    -e CHRONO_LOG_JSON=true \
    -e CHRONO_SERVER_HOST=0.0.0.0 \
    -e CHRONO_SERVER_PORT=3000 \
    -e "CHRONO_CORS_ORIGIN=http://localhost:${FRONTEND_PORT}" \
    -e CHRONO_CORS_CREDENTIALS=true \
    -e CHRONO_AUTH_ENABLED=true \
    -e CHRONO_AUTH_REQUIRE_DB_KEYS=true \
    -e CHRONO_AUTH_METRICS_API_KEYS="$METRICS_SCRAPE_KEY" \
    -e CHRONO_JWT_ENABLED="$JWT_ENABLED" \
    -e CHRONO_JWT_SECRET="$JWT_SECRET" \
    -e CHRONO_REDIS_ENABLED=true \
    -e CHRONO_REDIS_URL=redis://redis:6379 \
    -e CHRONO_QUEUE_ENABLED=true \
    -e CHRONO_OTEL_ENABLED="$OTEL_ENABLED" \
    -e CHRONO_OTEL_ENDPOINT=http://jaeger:4318 \
    -e CHRONO_INTELLIGENCE_PROVIDER="$INTELLIGENCE_PROVIDER" \
    -e CHRONO_INTELLIGENCE_API_KEY="$INTELLIGENCE_API_KEY" \
    -e CHRONO_INTELLIGENCE_BASE_URL="$INTELLIGENCE_BASE_URL" \
    -e CHRONO_INTELLIGENCE_MODEL="$INTELLIGENCE_MODEL" \
    -e CHRONO_STRIPE_ENABLED="$STRIPE_ENABLED" \
    -e CHRONO_STRIPE_SECRET_KEY="$STRIPE_SECRET_KEY" \
    -e CHRONO_STRIPE_PUBLISHABLE_KEY="$STRIPE_PUBLISHABLE_KEY" \
    -e CHRONO_STRIPE_WEBHOOK_SECRET="$STRIPE_WEBHOOK_SECRET" \
    -e CHRONO_SERVER_PUBLIC_URL="$SERVER_PUBLIC_URL" \
    -e CHRONO_ENCRYPTION_ENABLED=true \
    -e CHRONO_ENCRYPTION_MASTER_KEY="$ENCRYPTION_MASTER_KEY" \
    -e CHRONO_ENCRYPTION_DEFAULT_KEY_REF=master \
    -e CHRONO_ENCRYPTION_KEYRING_JSON="$ENCRYPTION_KEYRING_JSON" \
    -e CHRONO_WEBSOCKET_ENABLED=true \
    -e CHRONO_WEBSOCKET_HEARTBEAT_MS=30000 \
    -e CHRONO_OBSERVABILITY_WORKER_ENABLED=false \
    -e CHRONO_OBSERVABILITY_KAFKA_ENABLED=true \
    -e CHRONO_OBSERVABILITY_KAFKA_BROKERS=redpanda:9092 \
    -e CHRONO_OBSERVABILITY_KAFKA_TOPIC=observability.events \
    -e CHRONO_OBSERVABILITY_KAFKA_CONSUMER_GROUP_ID=chrono-synth-observability \
    -e CHRONO_OBSERVABILITY_KAFKA_STARTUP_WAIT_MS=45000 \
    --health-cmd 'node -e "const http=require(\"node:http\");const req=http.get(\"http://127.0.0.1:3000/healthz\",(res)=>process.exit(res.statusCode===200?0:1));req.on(\"error\",()=>process.exit(1));req.setTimeout(4000,()=>{req.destroy();process.exit(1);});"' \
    --health-interval 15s \
    --health-timeout 5s \
    --health-retries 8 \
    --health-start-period 20s \
    "$(backend_image)" >/dev/null
}

run_worker() {
  remove_container_if_exists "$WORKER_CONTAINER"
  "$ENGINE" run -d \
    --name "$WORKER_CONTAINER" \
    --network "$NETWORK_NAME" \
    --network-alias observability-worker \
    --restart unless-stopped \
    --label chrono.stack=chrono-synth \
    --label chrono.runtime=podman \
    -e CHRONO_DB_DRIVER=postgres \
    -e CHRONO_DB_CONNECTION_STRING="postgresql://chrono:${PG_PASSWORD}@postgres:5432/chrono_synth" \
    -e CHRONO_LOG_LEVEL="$LOG_LEVEL" \
    -e CHRONO_LOG_JSON=true \
    -e CHRONO_REDIS_ENABLED=false \
    -e CHRONO_QUEUE_ENABLED=false \
    -e CHRONO_OTEL_ENABLED="$OTEL_ENABLED" \
    -e CHRONO_OTEL_ENDPOINT=http://jaeger:4318 \
    -e CHRONO_OTEL_SERVICE_NAME=chrono-synth-observability-worker \
    -e CHRONO_ENCRYPTION_ENABLED=true \
    -e CHRONO_ENCRYPTION_MASTER_KEY="$ENCRYPTION_MASTER_KEY" \
    -e CHRONO_ENCRYPTION_DEFAULT_KEY_REF=master \
    -e CHRONO_ENCRYPTION_KEYRING_JSON="$ENCRYPTION_KEYRING_JSON" \
    -e CHRONO_OBSERVABILITY_WORKER_ENABLED=true \
    -e CHRONO_OBSERVABILITY_WORKER_HTTP_ENABLED=true \
    -e CHRONO_OBSERVABILITY_WORKER_HTTP_HOST=0.0.0.0 \
    -e CHRONO_OBSERVABILITY_WORKER_HTTP_PORT=3100 \
    -e CHRONO_OBSERVABILITY_KAFKA_ENABLED=true \
    -e CHRONO_OBSERVABILITY_KAFKA_BROKERS=redpanda:9092 \
    -e CHRONO_OBSERVABILITY_KAFKA_TOPIC=observability.events \
    -e CHRONO_OBSERVABILITY_KAFKA_CONSUMER_GROUP_ID=chrono-synth-observability \
    -e CHRONO_OBSERVABILITY_KAFKA_STARTUP_WAIT_MS=45000 \
    --health-cmd 'node -e "const http=require(\"node:http\");const req=http.get(\"http://127.0.0.1:3100/healthz\",(res)=>process.exit(res.statusCode===200?0:1));req.on(\"error\",()=>process.exit(1));req.setTimeout(4000,()=>{req.destroy();process.exit(1);});"' \
    --health-interval 15s \
    --health-timeout 5s \
    --health-retries 8 \
    --health-start-period 20s \
    "$(backend_image)" \
    node dist/main-observability-worker.js >/dev/null
}

run_prometheus() {
  remove_container_if_exists "$PROMETHEUS_CONTAINER"
  ensure_runtime_dir
  printf '%s' "$METRICS_SCRAPE_KEY" > "$RUNTIME_DIR/metrics-scrape-token"
  chmod 600 "$RUNTIME_DIR/metrics-scrape-token"
  "$ENGINE" run -d \
    --name "$PROMETHEUS_CONTAINER" \
    --network "$NETWORK_NAME" \
    --network-alias prometheus \
    --restart unless-stopped \
    --label chrono.stack=chrono-synth \
    --label chrono.runtime=podman \
    -v "$PROJECT_ROOT/podman/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro" \
    -v "$RUNTIME_DIR/metrics-scrape-token:/run/secrets/metrics-scrape-token:ro" \
    -v "${PROMETHEUS_VOLUME}:/prometheus" \
    --health-cmd "wget -qO- http://127.0.0.1:9090/prometheus/-/healthy" \
    --health-interval 15s \
    --health-timeout 5s \
    --health-retries 5 \
    --health-start-period 15s \
    "$PROMETHEUS_IMAGE" \
    --config.file=/etc/prometheus/prometheus.yml \
    --storage.tsdb.path=/prometheus \
    --storage.tsdb.retention.time=7d \
    --web.enable-lifecycle \
    --web.external-url="http://localhost:${FRONTEND_PORT}/prometheus/" \
    --web.route-prefix=/prometheus/ >/dev/null
}

run_grafana() {
  remove_container_if_exists "$GRAFANA_CONTAINER"
  "$ENGINE" run -d \
    --name "$GRAFANA_CONTAINER" \
    --network "$NETWORK_NAME" \
    --network-alias grafana \
    --restart unless-stopped \
    --label chrono.stack=chrono-synth \
    --label chrono.runtime=podman \
    -e GF_SECURITY_ADMIN_USER="$GRAFANA_ADMIN_USER" \
    -e GF_SECURITY_ADMIN_PASSWORD="$GRAFANA_ADMIN_PASSWORD" \
    -e GF_SERVER_ROOT_URL='%(protocol)s://%(domain)s/grafana/' \
    -e GF_SERVER_SERVE_FROM_SUB_PATH=true \
    -v "$PROJECT_ROOT/k8s/base/grafana/provisioning/datasources/datasources.yml:/etc/grafana/provisioning/datasources/datasources.yml:ro" \
    -v "$PROJECT_ROOT/k8s/base/grafana/provisioning/dashboards/dashboards.yml:/etc/grafana/provisioning/dashboards/dashboards.yml:ro" \
    -v "$PROJECT_ROOT/k8s/base/grafana/dashboards:/var/lib/grafana/dashboards:ro" \
    -v "${GRAFANA_VOLUME}:/var/lib/grafana" \
    --health-cmd "wget -qO- http://127.0.0.1:3000/api/health" \
    --health-interval 15s \
    --health-timeout 5s \
    --health-retries 10 \
    --health-start-period 20s \
    "$GRAFANA_IMAGE" >/dev/null
}

run_frontend() {
  remove_container_if_exists "$FRONTEND_CONTAINER"
  "$ENGINE" run -d \
    --name "$FRONTEND_CONTAINER" \
    --network "$NETWORK_NAME" \
    --network-alias frontend \
    --restart unless-stopped \
    --label chrono.stack=chrono-synth \
    --label chrono.runtime=podman \
    -e CHRONO_WEB_API_BASE_URL="$WEB_API_BASE_URL" \
    -e CHRONO_WEB_SENTRY_DSN="$WEB_SENTRY_DSN" \
    -e CHRONO_WEB_ENVIRONMENT="$WEB_ENVIRONMENT" \
    -p "${FRONTEND_PORT}:8080" \
    --health-cmd "wget -qO- http://127.0.0.1:8080/frontend-healthz >/dev/null || exit 1" \
    --health-interval 15s \
    --health-timeout 5s \
    --health-retries 5 \
    --health-start-period 10s \
    "$(frontend_image)" >/dev/null
}

print_access_urls() {
  echo ""
  info "服务已启动！"
  info "  前端:       http://localhost:${FRONTEND_PORT}"
  info "  后端:       http://localhost:${BACKEND_PORT}"
  info "  Jaeger:     http://localhost:${JAEGER_PORT}"
  info "  Worker:     http://localhost:${FRONTEND_PORT}/worker/healthz"
  info "  Prometheus: http://localhost:${FRONTEND_PORT}/prometheus/targets"
  info "  Grafana:    http://localhost:${FRONTEND_PORT}/grafana/d/chrono-synth-overview/chrono-synth-enterprise-overview"
}

stack_up() {
  load_env
  require_podman

  if [ "${PODMAN_SKIP_BUILD:-false}" != "true" ]; then
    build_images
  fi

  title "启动原生 Podman 本地环境"

  ensure_network
  ensure_volume "$PG_VOLUME"
  ensure_volume "$REDIS_VOLUME"
  ensure_volume "$REDPANDA_VOLUME"
  ensure_volume "$PROMETHEUS_VOLUME"
  ensure_volume "$GRAFANA_VOLUME"

  run_postgres
  run_redis
  run_redpanda
  run_jaeger
  wait_for_container_health "$POSTGRES_CONTAINER" 120
  wait_for_container_health "$REDIS_CONTAINER" 90
  wait_for_container_health "$REDPANDA_CONTAINER" 120
  wait_for_container_health "$JAEGER_CONTAINER" 90
  bootstrap_redpanda_topics

  run_backend
  wait_for_container_health "$BACKEND_CONTAINER" 180

  run_worker
  wait_for_container_health "$WORKER_CONTAINER" 180

  run_prometheus
  wait_for_container_health "$PROMETHEUS_CONTAINER" 120

  run_grafana
  wait_for_container_health "$GRAFANA_CONTAINER" 180

  run_frontend
  wait_for_http_ready "$FRONTEND_CONTAINER" "http://127.0.0.1:${FRONTEND_PORT}/frontend-healthz" 120 || {
    "$ENGINE" logs "$FRONTEND_CONTAINER" 2>/dev/null || true
    return 1
  }

  bash "$PROJECT_ROOT/scripts/health-check.sh" "http://localhost:${FRONTEND_PORT}" || true
  print_access_urls
}

stack_down() {
  require_podman
  title "停止原生 Podman 本地环境"

  for container in "${CONTAINERS[@]}"; do
    if container_exists "$container"; then
      info "移除容器: $container"
      "$ENGINE" rm -f "$container" >/dev/null
    fi
  done

  if "$ENGINE" network exists "$NETWORK_NAME" >/dev/null 2>&1; then
    info "移除网络: $NETWORK_NAME"
    "$ENGINE" network rm "$NETWORK_NAME" >/dev/null || true
  fi

  info "已停止"
}

stack_logs() {
  require_podman
  local container
  container="$(resolve_service_container "$TARGET_SERVICE")"
  exec "$ENGINE" logs -f "$container"
}

stack_build() {
  load_env
  require_podman
  build_images
}

case "$ACTION" in
  up)    stack_up ;;
  down)  stack_down ;;
  logs)  stack_logs ;;
  build) stack_build ;;
  *)
    error "未知操作: $ACTION (可选: up, down, logs, build)"
    exit 1
    ;;
esac

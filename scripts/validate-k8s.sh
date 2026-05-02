#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if command -v kustomize >/dev/null 2>&1; then
  KUSTOMIZE=(kustomize)
elif command -v kubectl >/dev/null 2>&1; then
  KUSTOMIZE=(kubectl kustomize)
else
  echo "[ERROR] 需要 kustomize 或 kubectl 才能渲染 overlays" >&2
  exit 1
fi

TMP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

pass() { printf '[PASS] %s\n' "$1"; }
fail() { printf '[FAIL] %s\n' "$1" >&2; exit 1; }

render_overlay() {
  local overlay="$1"
  "${KUSTOMIZE[@]}" "$PROJECT_ROOT/k8s/overlays/$overlay" > "$TMP_DIR/$overlay.yaml"
}

assert_contains() {
  local file="$1" pattern="$2" label="$3"
  if grep -Eq -- "$pattern" "$file"; then
    pass "$label"
  else
    fail "$label"
  fi
}

assert_count_at_least() {
  local file="$1" pattern="$2" minimum="$3" label="$4"
  local count
  count=$(grep -Ec -- "$pattern" "$file" || true)
  if [ "$count" -ge "$minimum" ]; then
    pass "$label"
  else
    fail "$label (found=$count, need>=$minimum)"
  fi
}

render_overlay dev
render_overlay staging
render_overlay prod

assert_contains "$TMP_DIR/dev.yaml" 'CHRONO_AUTH_ENABLED: "false"' 'dev 允许关闭 auth 以便本地调试'
assert_contains "$TMP_DIR/dev.yaml" 'CHRONO_WEB_ENVIRONMENT: development' 'dev frontend runtime environment 正确'

assert_contains "$TMP_DIR/staging.yaml" 'CHRONO_AUTH_ENABLED: "true"' 'staging 开启 auth'
assert_contains "$TMP_DIR/staging.yaml" 'CHRONO_AUTH_REQUIRE_DB_KEYS: "true"' 'staging 强制 DB key'
assert_contains "$TMP_DIR/staging.yaml" 'CHRONO_ENCRYPTION_ENABLED: "true"' 'staging 开启加密'
assert_contains "$TMP_DIR/staging.yaml" 'CHRONO_ENCRYPTION_KEYRING_JSON:' 'staging 暴露可配置的 encryption keyring secret'
assert_contains "$TMP_DIR/staging.yaml" 'CHRONO_OBSERVABILITY_KAFKA_ENABLED: "true"' 'staging 开启 Kafka 观测管线'
assert_contains "$TMP_DIR/staging.yaml" '--web.external-url=https://chrono.staging.local/prometheus/' 'staging Prometheus external URL 正确'

assert_contains "$TMP_DIR/prod.yaml" 'containerPort: 8080' 'prod frontend 使用 8080 容器端口'
assert_contains "$TMP_DIR/prod.yaml" 'runAsNonRoot: true' 'prod frontend 以非 root 运行'
assert_contains "$TMP_DIR/prod.yaml" 'frontend-healthz' 'prod frontend 暴露独立健康检查'
assert_contains "$TMP_DIR/prod.yaml" 'bearer_token_file: /etc/prometheus/secrets/metrics-scrape-token/token' 'prod Prometheus 使用 token 抓取 backend metrics'
assert_contains "$TMP_DIR/prod.yaml" 'name: prometheus-scrape-auth' 'prod 包含 metrics scrape secret'
assert_contains "$TMP_DIR/prod.yaml" 'CHRONO_AUTH_ENABLED: "true"' 'prod 开启 auth'
assert_contains "$TMP_DIR/prod.yaml" 'CHRONO_AUTH_REQUIRE_DB_KEYS: "true"' 'prod 强制 DB key'
assert_contains "$TMP_DIR/prod.yaml" 'CHRONO_ENCRYPTION_ENABLED: "true"' 'prod 开启加密'
assert_contains "$TMP_DIR/prod.yaml" 'CHRONO_ENCRYPTION_KEYRING_JSON:' 'prod 暴露可配置的 encryption keyring secret'
assert_contains "$TMP_DIR/prod.yaml" 'CHRONO_SERVER_PUBLIC_URL: https://chrono.example.com' 'prod public URL 正确'
assert_contains "$TMP_DIR/prod.yaml" 'CHRONO_OBSERVABILITY_KAFKA_ENABLED: "true"' 'prod 开启 Kafka 观测管线'
assert_contains "$TMP_DIR/prod.yaml" '--web.external-url=https://chrono.example.com/prometheus/' 'prod Prometheus external URL 正确'
assert_count_at_least "$TMP_DIR/prod.yaml" '^kind: PodDisruptionBudget$' 3 'prod 包含 backend/frontend/worker PDB'

printf '\n[OK] All overlays passed validation.\n'

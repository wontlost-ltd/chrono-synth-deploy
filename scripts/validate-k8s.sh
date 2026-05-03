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

# ── 数据平面权威模式 ───────────────────────────────────────────────────────────
# 确保所有 overlay 都声明了 CHRONO_DATA_PLANE_AUTHORITY_MODE，
# 防止环境变量缺失导致服务器以未知模式启动。
assert_contains "$TMP_DIR/dev.yaml"     'CHRONO_DATA_PLANE_AUTHORITY_MODE:' 'dev 声明数据平面权威模式'
assert_contains "$TMP_DIR/staging.yaml" 'CHRONO_DATA_PLANE_AUTHORITY_MODE:' 'staging 声明数据平面权威模式'
assert_contains "$TMP_DIR/prod.yaml"    'CHRONO_DATA_PLANE_AUTHORITY_MODE:' 'prod 声明数据平面权威模式'

# 生产环境默认必须是 tables_primary（最保守模式），
# 晋升到 dual_write/ledger_primary 须通过 Admin API per-tenant 控制，不能全局写死。
assert_contains "$TMP_DIR/prod.yaml" 'CHRONO_DATA_PLANE_AUTHORITY_MODE: "tables_primary"' \
  'prod 数据平面默认模式为 tables_primary（通过 Admin API 逐租户晋升）'

# ── KMS / Storage 提供方 ──────────────────────────────────────────────────────
assert_contains "$TMP_DIR/dev.yaml"     'CHRONO_KMS_PROVIDER:'     'dev 声明 KMS 提供方'
assert_contains "$TMP_DIR/staging.yaml" 'CHRONO_KMS_PROVIDER:'     'staging 声明 KMS 提供方'
assert_contains "$TMP_DIR/prod.yaml"    'CHRONO_KMS_PROVIDER:'     'prod 声明 KMS 提供方'
assert_contains "$TMP_DIR/dev.yaml"     'CHRONO_STORAGE_PROVIDER:' 'dev 声明对象存储提供方'
assert_contains "$TMP_DIR/staging.yaml" 'CHRONO_STORAGE_PROVIDER:' 'staging 声明对象存储提供方'
assert_contains "$TMP_DIR/prod.yaml"    'CHRONO_STORAGE_PROVIDER:' 'prod 声明对象存储提供方'

# ── BYOK 配置完整性 ───────────────────────────────────────────────────────────
# 若 overlay 声明了非 platform 的 KMS 提供方，则必须同时包含对应的 KMS Secret 引用，
# 防止 pod 以无效 KMS 配置启动（KMS 调用会失败但不会在启动时报错）。
for overlay_file in "$TMP_DIR/staging.yaml" "$TMP_DIR/prod.yaml"; do
  overlay_name="$(basename "$overlay_file" .yaml)"
  kms_provider="$(grep -oE 'CHRONO_KMS_PROVIDER:[[:space:]]+"?[a-z_]+"?' "$overlay_file" \
    | tail -1 | grep -oE '[a-z_]+$' || echo 'platform')"
  if [ "$kms_provider" != "platform" ]; then
    # 非 platform 模式必须存在 KMS secret 挂载或 SecretKeyRef 引用
    if ! grep -Eq 'CHRONO_KMS_|kms.*[Ss]ecret|[Ss]ecret.*kms' "$overlay_file"; then
      fail "$overlay_name: KMS 提供方为 '$kms_provider' 但未找到 KMS Secret 引用"
    else
      pass "$overlay_name: BYOK 非 platform 模式包含 KMS Secret 引用"
    fi
  else
    pass "$overlay_name: BYOK 使用 platform 模式（无需外部 KMS Secret）"
  fi
done

# ── Event Ledger / Projection Store 相关资源 ─────────────────────────────────
# Projection flush worker 由 CHRONO_OBSERVABILITY_WORKER_ENABLED 控制，
# staging 和 prod 必须明确声明该开关，防止投影消费者静默关闭导致 ledger 积压。
assert_contains "$TMP_DIR/staging.yaml" 'CHRONO_OBSERVABILITY_WORKER_ENABLED:' \
  'staging 声明 observability worker（event ledger projection consumer）'
assert_contains "$TMP_DIR/prod.yaml"    'CHRONO_OBSERVABILITY_WORKER_ENABLED:' \
  'prod 声明 observability worker（event ledger projection consumer）'

# 确认 staging/prod ConfigMap 包含 event ledger outbox topic 配置
assert_contains "$TMP_DIR/staging.yaml" 'CHRONO_OBSERVABILITY_KAFKA_TOPIC:' \
  'staging 声明 event ledger outbox Kafka topic'
assert_contains "$TMP_DIR/prod.yaml"    'CHRONO_OBSERVABILITY_KAFKA_TOPIC:' \
  'prod 声明 event ledger outbox Kafka topic'

printf '\n[OK] All overlays passed validation.\n'

#!/usr/bin/env bash
# 部署后健康检查
set -euo pipefail

BASE_URL="${1:-http://localhost:3000}"
MAX_RETRIES=30
RETRY_INTERVAL=5

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
warn()  { echo -e "${YELLOW}[WAIT]${NC} $1"; }

ENDPOINTS=(
  "/healthz:后端健康检查"
  "/readyz:后端就绪检查"
  "/:前端页面"
)

info "目标地址: $BASE_URL"
info "等待服务就绪..."

# 等待后端就绪
for ((i=1; i<=MAX_RETRIES; i++)); do
  if curl -sf "${BASE_URL}/healthz" >/dev/null 2>&1; then
    info "后端已就绪！(第 ${i} 次检查)"
    break
  fi
  if [ "$i" -eq "$MAX_RETRIES" ]; then
    error "后端未在 $((MAX_RETRIES * RETRY_INTERVAL)) 秒内就绪"
    exit 1
  fi
  warn "等待中... (${i}/${MAX_RETRIES})"
  sleep "$RETRY_INTERVAL"
done

# 检查所有端点
FAILED=0
for entry in "${ENDPOINTS[@]}"; do
  IFS=":" read -r path desc <<< "$entry"
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "${BASE_URL}${path}" 2>/dev/null || echo "000")
  if [ "$HTTP_CODE" -ge 200 ] && [ "$HTTP_CODE" -lt 400 ]; then
    info "  ✓ ${desc} (${path}) → HTTP ${HTTP_CODE}"
  else
    error "  ✗ ${desc} (${path}) → HTTP ${HTTP_CODE}"
    FAILED=$((FAILED + 1))
  fi
done

echo ""
if [ "$FAILED" -eq 0 ]; then
  info "所有健康检查通过！"
else
  error "${FAILED} 个检查失败"
  exit 1
fi

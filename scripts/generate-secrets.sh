#!/usr/bin/env bash
# 生成安全的密钥并更新 K8s Secret 文件
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }

# 生成随机密钥
JWT_SECRET=$(openssl rand -hex 32)
PG_PASSWORD=$(openssl rand -hex 16)

info "生成的密钥："
info "  JWT_SECRET:      ${JWT_SECRET}"
info "  PG_PASSWORD:     ${PG_PASSWORD}"
info ""

# 更新 backend secrets
BACKEND_SECRETS="$PROJECT_ROOT/k8s/base/backend/secrets.yaml"
if [ -f "$BACKEND_SECRETS" ]; then
  sed -i.bak \
    -e "s|CHANGE_ME_USE_openssl_rand_hex_32|${JWT_SECRET}|g" \
    -e "s|CHANGE_ME@|${PG_PASSWORD}@|g" \
    "$BACKEND_SECRETS"
  rm -f "${BACKEND_SECRETS}.bak"
  info "已更新: $BACKEND_SECRETS"
fi

# 更新 postgres secrets
PG_SECRETS="$PROJECT_ROOT/k8s/base/postgres/secrets.yaml"
if [ -f "$PG_SECRETS" ]; then
  sed -i.bak \
    -e "s|CHANGE_ME_USE_openssl_rand_hex_16|${PG_PASSWORD}|g" \
    "$PG_SECRETS"
  rm -f "${PG_SECRETS}.bak"
  info "已更新: $PG_SECRETS"
fi

# 更新 podman .env
PODMAN_ENV="$PROJECT_ROOT/podman/.env"
if [ -f "$PODMAN_ENV" ]; then
  sed -i.bak \
    -e "s|^PG_PASSWORD=.*|PG_PASSWORD=${PG_PASSWORD}|" \
    -e "s|^JWT_SECRET=.*|JWT_SECRET=${JWT_SECRET}|" \
    "$PODMAN_ENV"
  rm -f "${PODMAN_ENV}.bak"
  info "已更新: $PODMAN_ENV"
fi

warn "重要：请勿将生成的密钥提交到 Git！"
warn "建议将 secrets.yaml 加入 .gitignore 或使用 SealedSecrets/SOPS"

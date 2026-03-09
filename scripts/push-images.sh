#!/usr/bin/env bash
# 推送镜像到 GHCR
set -euo pipefail

REGISTRY="${REGISTRY:-ghcr.io/wontlost-ltd}"
TAG="${TAG:-latest}"
ENGINE="${ENGINE:-podman}"

GREEN='\033[0;32m'
NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $1"; }

# 检查登录状态
if ! $ENGINE login --get-login ghcr.io &>/dev/null 2>&1; then
  echo "请先登录 GHCR："
  echo "  echo \$GITHUB_TOKEN | $ENGINE login ghcr.io -u USERNAME --password-stdin"
  exit 1
fi

info "推送后端镜像..."
$ENGINE push "${REGISTRY}/chrono-synth-os:${TAG}"

info "推送前端镜像..."
$ENGINE push "${REGISTRY}/chrono-synth-web:${TAG}"

info "推送完成！"

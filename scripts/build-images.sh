#!/usr/bin/env bash
# 构建 chrono-synth-os 和 chrono-synth-web 容器镜像
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# 默认值
REGISTRY="${REGISTRY:-ghcr.io/wontlost-ltd}"
TAG="${TAG:-latest}"
ENGINE="${ENGINE:-podman}"

# 颜色
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }

# 源码路径（与 deploy 项目同级目录）。
# ADR-0049：前端 chrono-synth-web 已融合进 chrono-synth-os/apps/web，前后端同源于 monorepo。
BACKEND_SRC="${BACKEND_SRC:-$(cd "$PROJECT_ROOT/../chrono-synth-os" && pwd)}"
FRONTEND_SRC="${FRONTEND_SRC:-$BACKEND_SRC}"
# 前端 Dockerfile 在 apps/web 下，但 build context 必须是 monorepo 根（workspace 包解析）。
FRONTEND_DOCKERFILE="${FRONTEND_DOCKERFILE:-$FRONTEND_SRC/apps/web/Dockerfile}"

# 验证源码目录
if [ ! -f "$BACKEND_SRC/Dockerfile" ]; then
  echo "错误：找不到后端 Dockerfile: $BACKEND_SRC/Dockerfile" >&2
  echo "请设置 BACKEND_SRC 环境变量指向 chrono-synth-os 目录" >&2
  exit 1
fi

if [ ! -f "$FRONTEND_DOCKERFILE" ]; then
  echo "错误：找不到前端 Dockerfile: $FRONTEND_DOCKERFILE" >&2
  echo "请设置 FRONTEND_SRC 指向 chrono-synth-os 目录（apps/web/Dockerfile 在其下）" >&2
  exit 1
fi

info "容器引擎: $ENGINE"
info "镜像仓库: $REGISTRY"
info "镜像标签: $TAG"
info ""

# 构建后端
info "构建后端镜像: ${REGISTRY}/chrono-synth-os:${TAG}"
$ENGINE build \
  -t "${REGISTRY}/chrono-synth-os:${TAG}" \
  -f "$BACKEND_SRC/Dockerfile" \
  "$BACKEND_SRC"

info ""

# 构建前端（context = monorepo 根，Dockerfile = apps/web/Dockerfile）
info "构建前端镜像: ${REGISTRY}/chrono-synth-web:${TAG}"
$ENGINE build \
  -t "${REGISTRY}/chrono-synth-web:${TAG}" \
  -f "$FRONTEND_DOCKERFILE" \
  "$FRONTEND_SRC"

info ""
info "构建完成！"
info "  后端: ${REGISTRY}/chrono-synth-os:${TAG}"
info "  前端: ${REGISTRY}/chrono-synth-web:${TAG}"

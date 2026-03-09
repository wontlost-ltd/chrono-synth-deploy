#!/usr/bin/env bash
# 将本地镜像导入 k3s（无 registry 模式）
set -euo pipefail

REGISTRY="${REGISTRY:-ghcr.io/rpang}"
TAG="${TAG:-latest}"
ENGINE="${ENGINE:-podman}"

GREEN='\033[0;32m'
NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $1"; }

TMPDIR="${TMPDIR:-/tmp}"

for IMAGE in "chrono-synth-os" "chrono-synth-web"; do
  FULL="${REGISTRY}/${IMAGE}:${TAG}"
  TARFILE="${TMPDIR}/${IMAGE}-${TAG}.tar"

  info "导出 ${FULL} → ${TARFILE}"
  $ENGINE save -o "$TARFILE" "$FULL"

  info "导入 ${TARFILE} → k3s"
  sudo k3s ctr images import "$TARFILE"

  rm -f "$TARFILE"
done

info "导入完成！"
info "验证: sudo k3s ctr images ls | grep chrono"

#!/usr/bin/env bash
# ChronoSynth 一键部署脚本
# 支持 k3s 集群部署和本地 podman 测试
#
# 用法:
#   ./deploy.sh k3s [dev|staging|prod]    # 部署到 k3s
#   ./deploy.sh podman [up|down|logs]     # 本地 podman 测试
#   ./deploy.sh build [--push]            # 构建镜像（可选推送）
#   ./deploy.sh status                    # 查看部署状态
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
title() { echo -e "\n${BLUE}=== $1 ===${NC}\n"; }

# 默认配置
REGISTRY="${REGISTRY:-ghcr.io/rpang}"
TAG="${TAG:-latest}"
ENGINE="${ENGINE:-podman}"
NAMESPACE="chrono-synth"

usage() {
  echo "ChronoSynth 部署工具"
  echo ""
  echo "用法:"
  echo "  $0 k3s [dev|staging|prod]    部署到 k3s 集群"
  echo "  $0 podman [up|down|logs]     本地 podman 容器测试"
  echo "  $0 build [--push]            构建并可选推送镜像"
  echo "  $0 status                    查看 k3s 部署状态"
  echo "  $0 secrets                   生成安全密钥"
  echo ""
  echo "环境变量:"
  echo "  REGISTRY   镜像仓库 (默认: ghcr.io/rpang)"
  echo "  TAG        镜像标签 (默认: latest)"
  echo "  ENGINE     容器引擎 (默认: podman)"
}

# ── k3s 部署 ──
deploy_k3s() {
  local ENV="${1:-dev}"

  if [ ! -d "$SCRIPT_DIR/k8s/overlays/$ENV" ]; then
    error "未知环境: $ENV (可选: dev, staging, prod)"
    exit 1
  fi

  title "部署 ChronoSynth 到 k3s [$ENV]"

  # 检查 kubectl
  if ! command -v kubectl &>/dev/null; then
    error "kubectl 未安装"
    exit 1
  fi

  # 检查集群连接
  if ! kubectl cluster-info &>/dev/null; then
    error "无法连接 k3s 集群，请检查 KUBECONFIG"
    exit 1
  fi

  # 检查镜像是否存在
  info "检查镜像..."
  for IMAGE in chrono-synth-os chrono-synth-web; do
    if ! $ENGINE image exists "${REGISTRY}/${IMAGE}:${TAG}" 2>/dev/null; then
      warn "镜像 ${REGISTRY}/${IMAGE}:${TAG} 不存在，开始构建..."
      bash "$SCRIPT_DIR/scripts/build-images.sh"
      break
    fi
  done

  # 检查镜像加载方式
  if kubectl get nodes -o jsonpath='{.items[0].status.nodeInfo.containerRuntimeVersion}' 2>/dev/null | grep -q containerd; then
    info "检测到 k3s containerd，导入镜像..."
    bash "$SCRIPT_DIR/scripts/import-k3s.sh"
  else
    info "假设镜像已在 registry 中可用"
  fi

  # 渲染并部署
  info "应用 Kustomize overlay: $ENV"
  kubectl apply -k "$SCRIPT_DIR/k8s/overlays/$ENV"

  # 等待 rollout
  info "等待部署完成..."
  kubectl -n "$NAMESPACE" rollout status deployment/chrono-synth-os --timeout=120s || true
  kubectl -n "$NAMESPACE" rollout status deployment/chrono-synth-web --timeout=120s || true
  kubectl -n "$NAMESPACE" rollout status statefulset/postgres --timeout=120s || true
  kubectl -n "$NAMESPACE" rollout status statefulset/redis --timeout=60s || true

  # 状态
  echo ""
  info "部署状态："
  kubectl -n "$NAMESPACE" get pods -o wide
  echo ""
  kubectl -n "$NAMESPACE" get svc
  echo ""
  kubectl -n "$NAMESPACE" get ingress 2>/dev/null || true

  title "部署完成！"

  # 获取 Ingress 地址
  local INGRESS_IP
  INGRESS_IP=$(kubectl -n "$NAMESPACE" get ingress chrono-synth-ingress -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
  if [ -n "$INGRESS_IP" ]; then
    info "访问地址: http://${INGRESS_IP}"
  else
    local NODE_IP
    NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || echo "localhost")
    info "NodePort 访问: 使用 kubectl -n $NAMESPACE port-forward svc/chrono-synth-web 8080:80"
    info "然后访问: http://localhost:8080"
  fi
}

# ── podman 本地测试 ──
deploy_podman() {
  local ACTION="${1:-up}"
  local COMPOSE_FILE="$SCRIPT_DIR/podman/podman-compose.yml"
  local ENV_FILE="$SCRIPT_DIR/podman/.env"

  if [ ! -f "$ENV_FILE" ]; then
    warn ".env 文件不存在，从模板创建..."
    cp "$SCRIPT_DIR/podman/.env.example" "$ENV_FILE"
    info "已创建 $ENV_FILE，请根据需要修改配置"
  fi

  case "$ACTION" in
    up)
      title "启动 podman 本地环境"
      $ENGINE-compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d
      echo ""
      info "等待服务就绪..."
      sleep 10
      bash "$SCRIPT_DIR/scripts/health-check.sh" "http://localhost:$(grep FRONTEND_PORT "$ENV_FILE" 2>/dev/null | cut -d= -f2 || echo 80)" || true
      echo ""
      info "服务已启动！"
      info "  前端:    http://localhost:$(grep FRONTEND_PORT "$ENV_FILE" 2>/dev/null | cut -d= -f2 || echo 80)"
      info "  后端:    http://localhost:$(grep BACKEND_PORT "$ENV_FILE" 2>/dev/null | cut -d= -f2 || echo 3000)"
      info "  Jaeger:  http://localhost:$(grep JAEGER_PORT "$ENV_FILE" 2>/dev/null | cut -d= -f2 || echo 16686)"
      ;;
    down)
      title "停止 podman 本地环境"
      $ENGINE-compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" down
      info "已停止"
      ;;
    logs)
      $ENGINE-compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" logs -f "${2:-}"
      ;;
    build)
      title "构建本地镜像"
      $ENGINE-compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" build
      ;;
    *)
      error "未知操作: $ACTION (可选: up, down, logs, build)"
      exit 1
      ;;
  esac
}

# ── 构建镜像 ──
build_images() {
  title "构建容器镜像"
  bash "$SCRIPT_DIR/scripts/build-images.sh"

  if [ "${1:-}" = "--push" ]; then
    title "推送镜像到 GHCR"
    bash "$SCRIPT_DIR/scripts/push-images.sh"
  fi
}

# ── 查看状态 ──
show_status() {
  title "ChronoSynth 部署状态"

  if ! kubectl cluster-info &>/dev/null 2>&1; then
    warn "无法连接 k3s 集群"
    echo ""
    info "本地 podman 容器状态："
    $ENGINE ps --filter "name=chrono" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || echo "无运行中的容器"
    return
  fi

  echo "Pods:"
  kubectl -n "$NAMESPACE" get pods -o wide 2>/dev/null || warn "namespace $NAMESPACE 不存在"
  echo ""
  echo "Services:"
  kubectl -n "$NAMESPACE" get svc 2>/dev/null || true
  echo ""
  echo "Ingress:"
  kubectl -n "$NAMESPACE" get ingress 2>/dev/null || true
  echo ""
  echo "PVC:"
  kubectl -n "$NAMESPACE" get pvc 2>/dev/null || true
}

# ── 主入口 ──
case "${1:-help}" in
  k3s)     deploy_k3s "${2:-dev}" ;;
  podman)  deploy_podman "${2:-up}" "${3:-}" ;;
  build)   build_images "${2:-}" ;;
  status)  show_status ;;
  secrets) bash "$SCRIPT_DIR/scripts/generate-secrets.sh" ;;
  help|*)  usage ;;
esac

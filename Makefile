# ChronoSynth 部署快捷命令
.PHONY: help build push k3s-dev k3s-staging k3s-prod podman-up podman-down podman-logs status secrets clean

REGISTRY ?= ghcr.io/wontlost-ltd
TAG ?= latest
ENGINE ?= podman
ENV ?= dev

help: ## 显示帮助
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

build: ## 构建镜像
	REGISTRY=$(REGISTRY) TAG=$(TAG) ENGINE=$(ENGINE) bash scripts/build-images.sh

push: ## 推送镜像到 GHCR
	REGISTRY=$(REGISTRY) TAG=$(TAG) ENGINE=$(ENGINE) bash scripts/push-images.sh

k3s-dev: ## 部署到 k3s (dev)
	./deploy.sh k3s dev

k3s-staging: ## 部署到 k3s (staging)
	./deploy.sh k3s staging

k3s-prod: ## 部署到 k3s (prod)
	./deploy.sh k3s prod

podman-up: ## 启动本地 podman 环境
	./deploy.sh podman up

podman-down: ## 停止本地 podman 环境
	./deploy.sh podman down

podman-logs: ## 查看本地 podman 日志
	./deploy.sh podman logs

podman-build: ## 构建本地 podman 镜像
	./deploy.sh podman build

status: ## 查看部署状态
	./deploy.sh status

secrets: ## 生成安全密钥
	./deploy.sh secrets

render: ## 渲染 Kustomize（预览）
	kubectl kustomize k8s/overlays/$(ENV)

clean: ## 清理本地容器和卷
	./deploy.sh podman down
	$(ENGINE) volume prune -f

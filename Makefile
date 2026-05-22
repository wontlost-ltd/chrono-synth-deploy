# ChronoSynth 部署快捷命令
.PHONY: help build push k3s-dev k3s-staging k3s-prod podman-up podman-down podman-logs e2e status secrets conformance conformance-offline lint-compliance clean

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

e2e: ## 运行 E2E 测试（需先 podman-up）
	bash scripts/e2e-test.sh

status: ## 查看部署状态
	./deploy.sh status

secrets: ## 生成安全密钥
	./deploy.sh secrets

render: ## 渲染 Kustomize（预览）
	kubectl kustomize k8s/overlays/$(ENV)

conformance: ## 运行 portability conformance suite（需后端运行）
	bash scripts/portability-conformance.sh

conformance-offline: ## 运行 portability conformance suite（离线/schema 模式）
	bash scripts/portability-conformance.sh --offline

lint-compliance: ## 校验 Kyverno 策略 + ArgoCD 部署链路（GA Step 7）
	bash scripts/lint-compliance.sh

clean: ## 清理本地容器和卷
	./deploy.sh podman down
	$(ENGINE) volume prune -f

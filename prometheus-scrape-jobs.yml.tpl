# 共享 scrape job 模板 — 不可直接部署
# 被 podman/prometheus/prometheus.yml 和 k8s/base/prometheus/prometheus.yml 引用
#
# 环境差异汇总（每次更新两份文件时同步）：
#
#   变量                  podman                                     k8s
#   ------------------    ----------------------------------------   ------------------------------------------
#   ENVIRONMENT           podman                                     k8s
#   BACKEND_TARGET        backend:3000                               chrono-synth-os:3000
#   BEARER_TOKEN_FILE     /run/secrets/metrics-scrape-token          /etc/prometheus/secrets/metrics-scrape-token/token
#
# scrape job 规范（保持三个文件一致）：
#
# job: chrono-synth-backend
#   metrics_path: /metrics/prometheus
#   bearer_token_file: <BEARER_TOKEN_FILE>
#   target: <BACKEND_TARGET>
#   labels: service=chrono-synth-os, environment=<ENVIRONMENT>
#
# job: chrono-synth-observability-worker
#   metrics_path: /metrics
#   target: observability-worker:3100
#   labels: service=observability-worker, environment=<ENVIRONMENT>
#
# job: prometheus-self
#   target: localhost:9090
#   labels: environment=<ENVIRONMENT>

global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: chrono-synth-backend
    metrics_path: /metrics/prometheus
    bearer_token_file: <BEARER_TOKEN_FILE>
    static_configs:
      - targets:
          - <BACKEND_TARGET>
        labels:
          service: chrono-synth-os
          environment: <ENVIRONMENT>

  - job_name: chrono-synth-observability-worker
    metrics_path: /metrics
    static_configs:
      - targets:
          - observability-worker:3100
        labels:
          service: observability-worker
          environment: <ENVIRONMENT>

  - job_name: prometheus-self
    static_configs:
      - targets:
          - localhost:9090
        labels:
          environment: <ENVIRONMENT>

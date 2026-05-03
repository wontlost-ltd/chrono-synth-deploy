# 数据平面迁移操作手册

本手册指导将 ChronoSynth 数据平面从 `tables_primary` 逐步晋升到 `ledger_primary`，
以及在需要时执行回滚。每个步骤都是可独立验证的，每个阶段都有明确的回滚路径。

## 前提条件

- `chrono-synth-os` 版本已包含 `DataPlaneWriteCoordinator` 和 `ProjectionDriftChecker`（P1-3 完成后）
- 目标租户已完成数据备份
- 监控告警已就绪（Prometheus + Grafana 仪表盘可查看 `data_plane_authority_mode` 指标）
- 具备 Admin API 访问权限（需要 `admin` 角色 JWT）

---

## 阶段一：tables_primary → dual_write

### 说明

在此阶段，所有写操作同时写入关系表（source of truth）和 event ledger outbox。
读操作继续来自关系表。Projection consumer 和 drift checker 在后台运行，但不影响业务读路径。

### 步骤

**1. 确认 Projection Runner 正常运行**

```bash
# 检查 projection consumer 健康状态
curl -s -H "Authorization: Bearer $ADMIN_JWT" \
  "$BACKEND_URL/api/v1/admin/data-plane/projection-status" | jq .

# 期望输出示例：
# { "status": "running", "lagMs": 0, "lastConsumedAt": "2026-05-03T..." }
```

**2. 切换目标租户到 dual_write**

```bash
TENANT_ID=<your-tenant-id>

curl -s -X PATCH \
  -H "Authorization: Bearer $ADMIN_JWT" \
  -H "Content-Type: application/json" \
  -d '{"authorityMode": "dual_write"}' \
  "$BACKEND_URL/api/v1/admin/tenants/$TENANT_ID/data-plane-authority"
```

**3. 验证 dual_write 生效**

```bash
# 查询当前模式
curl -s -H "Authorization: Bearer $ADMIN_JWT" \
  "$BACKEND_URL/api/v1/admin/tenants/$TENANT_ID/data-plane-authority" | jq .authorityMode
# 期望："dual_write"

# 执行一次写操作，确认 outbox 有记录
curl -s -H "Authorization: Bearer $ADMIN_JWT" \
  "$BACKEND_URL/api/v1/admin/tenants/$TENANT_ID/data-plane/outbox-stats" | jq .
```

**4. 运行 Backfill（历史数据补录到 event ledger）**

```bash
curl -s -X POST \
  -H "Authorization: Bearer $ADMIN_JWT" \
  -H "Content-Type: application/json" \
  -d '{"tables": ["memory_nodes", "persona_core", "identities", "tasks"], "batchSize": 500}' \
  "$BACKEND_URL/api/v1/admin/tenants/$TENANT_ID/data-plane/backfill"

# 轮询 backfill 状态（直到 status=completed）
curl -s -H "Authorization: Bearer $ADMIN_JWT" \
  "$BACKEND_URL/api/v1/admin/tenants/$TENANT_ID/data-plane/backfill/status" | jq .
```

**5. 监控 dual_write 稳定性（建议观察 24–48 小时）**

关注 Grafana 面板中的：
- `chrono_data_plane_outbox_backlog`：outbox 积压量，应趋近 0
- `chrono_data_plane_projection_lag_ms`：投影延迟，应 < 1000ms
- `chrono_data_plane_dual_write_error_total`：双写错误数，应为 0

### 回滚（dual_write → tables_primary）

```bash
curl -s -X PATCH \
  -H "Authorization: Bearer $ADMIN_JWT" \
  -H "Content-Type: application/json" \
  -d '{"authorityMode": "tables_primary"}' \
  "$BACKEND_URL/api/v1/admin/tenants/$TENANT_ID/data-plane-authority"
```

无 schema 变更，立即生效。

---

## 阶段二：dual_write → ledger_primary（晋升）

### 前置条件检查（**必须全部通过才能晋升**）

**1. Projection drift 为零**

```bash
curl -s -H "Authorization: Bearer $ADMIN_JWT" \
  "$BACKEND_URL/api/v1/admin/tenants/$TENANT_ID/data-plane/drift-report" | jq .

# 必须满足：
# { "checked": N, "mismatched": 0, "missingProjection": 0, "missingTable": 0 }
```

**2. Outbox 积压为零**

```bash
curl -s -H "Authorization: Bearer $ADMIN_JWT" \
  "$BACKEND_URL/api/v1/admin/tenants/$TENANT_ID/data-plane/outbox-stats" | jq .pendingCount
# 必须为 0
```

**3. Ledger event count 与 table row count 一致**

```bash
curl -s -H "Authorization: Bearer $ADMIN_JWT" \
  "$BACKEND_URL/api/v1/admin/tenants/$TENANT_ID/data-plane/parity-report" | jq .
# matched: true
```

### 晋升步骤

```bash
# 晋升
curl -s -X PATCH \
  -H "Authorization: Bearer $ADMIN_JWT" \
  -H "Content-Type: application/json" \
  -d '{"authorityMode": "ledger_primary"}' \
  "$BACKEND_URL/api/v1/admin/tenants/$TENANT_ID/data-plane-authority"

# 确认
curl -s -H "Authorization: Bearer $ADMIN_JWT" \
  "$BACKEND_URL/api/v1/admin/tenants/$TENANT_ID/data-plane-authority" | jq .authorityMode
# 期望："ledger_primary"
```

### 晋升后验证

```bash
# 执行一次写操作（通过业务 API），确认响应正常
# 再次运行 drift check，确认晋升后仍为零 mismatch
curl -s -H "Authorization: Bearer $ADMIN_JWT" \
  "$BACKEND_URL/api/v1/admin/tenants/$TENANT_ID/data-plane/drift-report" | jq .mismatched
# 期望：0
```

---

## 阶段三：回滚演练（ledger_primary → rollback_tables）

在进行第一次生产晋升前，**必须先在 staging 完成此演练**。

### 步骤

```bash
# 1. 切回 rollback_tables
curl -s -X PATCH \
  -H "Authorization: Bearer $ADMIN_JWT" \
  -H "Content-Type: application/json" \
  -d '{"authorityMode": "rollback_tables"}' \
  "$BACKEND_URL/api/v1/admin/tenants/$TENANT_ID/data-plane-authority"

# 2. 确认模式切换
curl -s -H "Authorization: Bearer $ADMIN_JWT" \
  "$BACKEND_URL/api/v1/admin/tenants/$TENANT_ID/data-plane-authority" | jq .authorityMode
# 期望："rollback_tables"

# 3. 执行写操作（应路由到关系表）
# 4. 执行读操作（应来自关系表，响应正常）
# 5. 演练通过后，按需切回 ledger_primary 或 tables_primary
```

### 注意事项

- `rollback_tables` 状态下，ledger 停止写入，但历史 ledger 记录不受影响
- rollback 后在 ledger_primary 阶段产生的写入仍保留在 ledger 中，标记为 non-authoritative
- 不需要任何 schema 变更，所有切换都是运行时配置

---

## 全局默认模式变更

如需修改**所有新租户**的默认模式（影响 `tables_primary` 默认值）：

**Kubernetes（k8s/base/backend/configmap.yaml）**：
```yaml
CHRONO_DATA_PLANE_AUTHORITY_MODE: "dual_write"  # 改为所需模式
```
然后 `kubectl apply -k k8s/overlays/<env>`，重启 backend Pod。

**Podman（podman/.env）**：
```bash
CHRONO_DATA_PLANE_AUTHORITY_MODE=dual_write
```
然后 `./deploy.sh podman up`。

---

## 监控指标参考

| 指标 | 含义 | 告警阈值 |
|------|------|---------|
| `chrono_data_plane_authority_mode` | 当前模式（label: tenant_id） | — |
| `chrono_data_plane_outbox_backlog` | outbox 未 flush 数量 | > 1000 持续 5min |
| `chrono_data_plane_projection_lag_ms` | 投影消费延迟 | > 5000ms 持续 2min |
| `chrono_data_plane_dual_write_error_total` | 双写错误计数 | > 0 |
| `chrono_data_plane_drift_mismatches_total` | drift checker 不匹配数 | > 0 |

---

## 常见问题

**Q: dual_write 阶段 outbox 积压一直不清零？**

检查 observability worker 是否正常运行（`/worker/healthz`），查看 Kafka consumer group lag（若启用 Kafka 模式），或检查 outbox flush worker 日志。

**Q: drift check 报告 mismatched > 0？**

不要晋升到 ledger_primary。先查询 drift report 中的具体不匹配实体，检查是否存在并发写入时序问题。可以重新触发 projection rebuild 后再次检查。

**Q: 晋升后写操作变慢？**

ledger_primary 模式下，写路径增加了 event append + optional sync projection。检查 `chrono_data_plane_projection_lag_ms`，若投影延迟高，考虑增加 projection consumer 实例数。

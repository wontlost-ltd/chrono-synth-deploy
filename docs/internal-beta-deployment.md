# 内测部署指引（NAS + Oracle Cloud）

**配套文档**：`docs/release/internal-beta-checklist.md`（chrono-synth-os 仓）
**前置条件**：已完成 §8 双审 89/100 PASS，3 个 commit 合入 main
**生效版本**：包含 commits `0130e76`（JWT 热轮换）/ `f799ac1`（KMS 锚定 evidence）/ `31f6825`（Web Zod 边界解析）

---

## 拓扑

```
┌──────────────────────────┐    ┌──────────────────────────┐
│  Synology NAS（主）      │    │  Oracle Cloud（多实例）   │
│  ─────────────────────   │    │  ─────────────────────   │
│  Docker Compose          │    │  2× OCI Compute          │
│  • chrono-synth-os ×1    │    │  • chrono-synth-os ×2    │
│  • chrono-synth-web ×1   │    │  共享 PostgreSQL         │
│  • PostgreSQL            │    │  (OCI MySQL 或外置)      │
│  • Redis (可选)          │    │  + Redis Cluster         │
│  • Caddy reverse proxy   │    │  + LoadBalancer          │
└──────────────────────────┘    └──────────────────────────┘
        │                                  │
        └────── 浏览器/手机/平板 ──────────┘
```

---

## 1. Synology NAS 部署（单节点）

### 1.1 前提

| 项 | 要求 |
|----|------|
| DSM 版本 | ≥ 7.2 |
| 内存 | ≥ 4 GB |
| 存储 | ≥ 50 GB SSD volume |
| Docker | 已安装 Container Manager（旧称 Docker） |
| 外网 | 443 端口可入站（或配 Cloudflare Tunnel） |

### 1.2 准备 docker-compose.yml

把以下内容存到 NAS `/volume1/docker/chrono-synth/docker-compose.yml`：

```yaml
version: '3.9'

services:
  postgres:
    image: postgres:16-alpine
    restart: unless-stopped
    environment:
      POSTGRES_DB: chrono
      POSTGRES_USER: chrono
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    volumes:
      - ./data/postgres:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U chrono"]
      interval: 10s
      timeout: 5s
      retries: 5

  os:
    image: ghcr.io/wontlost-ltd/chrono-synth-os:beta-${TAG:-latest}
    restart: unless-stopped
    depends_on:
      postgres:
        condition: service_healthy
    environment:
      # 必填
      DATABASE_URL: postgres://chrono:${POSTGRES_PASSWORD}@postgres:5432/chrono
      JWT_ENABLED: 'true'
      JWT_ALGORITHM: RS256
      JWT_ISSUER: https://chrono.beta.${YOUR_DOMAIN}
      JWT_ACCESS_TTL_MS: 900000          # 15 分钟
      JWT_REFRESH_TTL_MS: 2592000000     # 30 天
      JWT_KEYS_JSON: ${JWT_KEYS_JSON}    # 详 1.3 节
      SQLCIPHER_KEY: ${SQLCIPHER_KEY}    # 32 字节 hex
      AUTH_ENABLED: 'true'
      # 锚定（内测必须开启以验证 KMS 失败 evidence）
      FEATURE_FLAG_AUDIT_KMS_SIGN_CHAIN_TAIL: 'true'
      AUDIT_KMS_ENDPOINT: ${AUDIT_KMS_ENDPOINT}
      AUDIT_KMS_KEY_ID: ${AUDIT_KMS_KEY_ID}
      AUDIT_ANCHOR_INTERVAL_MS: '60000'  # 内测调短，便于观察
      # 观察性
      OTEL_EXPORTER_OTLP_ENDPOINT: ${OTEL_ENDPOINT:-}
      LOG_LEVEL: info
    ports:
      - "127.0.0.1:3001:3001"  # 仅本地，由 caddy 反代
    volumes:
      - ./data/os:/app/data
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://localhost:3001/healthz"]
      interval: 15s
      timeout: 5s
      retries: 5

  web:
    image: ghcr.io/wontlost-ltd/chrono-synth-web:beta-${TAG:-latest}
    restart: unless-stopped
    depends_on:
      - os
    environment:
      CHRONO_WEB_API_BASE_URL: https://chrono.beta.${YOUR_DOMAIN}/api
      CHRONO_WEB_ENVIRONMENT: beta
      CHRONO_WEB_SENTRY_DSN: ${SENTRY_DSN:-}
    ports:
      - "127.0.0.1:8080:80"

  caddy:
    image: caddy:2-alpine
    restart: unless-stopped
    depends_on:
      - os
      - web
    ports:
      - "443:443"
      - "80:80"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - ./data/caddy/data:/data
      - ./data/caddy/config:/config
```

### 1.3 生成 JWT 密钥（关键 — 热轮换验证用）

```bash
cd /volume1/docker/chrono-synth

# 生成两对 RS256 密钥：第一对作 active，第二对作 grace（预备 rotate）
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out k1.priv.pem
openssl rsa -in k1.priv.pem -pubout -out k1.pub.pem
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out k2.priv.pem
openssl rsa -in k2.priv.pem -pubout -out k2.pub.pem

# 用 jq 拼成 JWT_KEYS_JSON
cat <<EOF > .env
POSTGRES_PASSWORD=$(openssl rand -hex 24)
SQLCIPHER_KEY=$(openssl rand -hex 32)
YOUR_DOMAIN=example.com
JWT_KEYS_JSON='[
  {"kid":"kid-beta-1","state":"active","algorithm":"RS256","privateKey":"'"$(awk '{printf "%s\\n", $0}' k1.priv.pem)"'","publicKey":"'"$(awk '{printf "%s\\n", $0}' k1.pub.pem)"'","secret":""},
  {"kid":"kid-beta-2","state":"grace","algorithm":"RS256","privateKey":"'"$(awk '{printf "%s\\n", $0}' k2.priv.pem)"'","publicKey":"'"$(awk '{printf "%s\\n", $0}' k2.pub.pem)"'","secret":""}
]'
AUDIT_KMS_ENDPOINT=https://kms.example.com/v1/keys/audit-anchor:sign
AUDIT_KMS_KEY_ID=audit-anchor-beta
EOF

# 锁权限（包含密钥）
chmod 600 .env k1.priv.pem k2.priv.pem
```

> ⚠️ **`JWT_KEYS_JSON` 中的私钥要换行转 `\n`**。`awk '{printf "%s\\n", $0}'` 帮你处理；如果手工写 yaml 请用 `|-` block scalar。

### 1.4 Caddyfile

```
chrono.beta.{$YOUR_DOMAIN} {
    encode gzip

    # SSE 长连接：禁用 buffering + 拉长超时
    handle /api/v1/feature-flags/stream {
        reverse_proxy os:3001 {
            transport http {
                read_timeout 24h
            }
            flush_interval -1
        }
    }

    handle /api/* {
        reverse_proxy os:3001
    }

    handle /.well-known/jwks.json {
        reverse_proxy os:3001
    }

    handle {
        reverse_proxy web:80
    }
}
```

### 1.5 启动

```bash
cd /volume1/docker/chrono-synth
docker compose up -d
docker compose ps        # 等所有服务 healthy

# 看启动日志确认 SQLCipher / KeyRing 装载成功
docker compose logs os | grep -E "(SQLCipher|KeyRing|active kid|listening)"
```

预期输出片段：

```
... os | SQLCipher boot key loaded (32 bytes)
... os | KeyRing loaded from jwt_signing_keys: 2 keys, active=kid-beta-1
... os | listening on :3001
```

### 1.6 验证检查表（对应 NAS-01 ~ NAS-06）

参考 `internal-beta-checklist.md` 中的 NAS 必须用例。

---

## 2. Oracle Cloud 多实例部署

### 2.1 资源规划

| 资源 | 规格 | 用途 |
|------|------|------|
| Compute A | VM.Standard.E4.Flex 2 OCPU / 8 GB | os pod A |
| Compute B | VM.Standard.E4.Flex 2 OCPU / 8 GB | os pod B |
| Database | MySQL HeatWave 或自建 PostgreSQL | 共享 DB |
| LoadBalancer | OCI LB 10 Mbps | 443 入站 |
| Vault | OCI KMS Master Key | 审计锚 + JWT 静态密钥保管 |

### 2.2 关键差异点（与 NAS 单节点对比）

| 项 | NAS | OCI 多实例 |
|----|-----|------------|
| `JWT_KEYS_JSON` | 启动种子 | 启动种子；**必须**先在两个 pod 间一致 |
| `JWT_KEY_STORE_RELOAD_MS` | 不需要 | **60000** — 多实例同步必备 |
| 锚定 service | 单实例直跑 | **每个 pod 都跑**；DB UNIQUE 索引保证幂等 |
| Feature flag SSE | 单一来源 | 客户端可能连任一 pod；广播必须经 DB 广播表 |
| SQLCipher | 启用 | **禁用**（PostgreSQL 已 at-rest 加密） |

### 2.3 docker-compose.override.yml（OCI 专用差异）

在 NAS 用的 compose 之上叠加：

```yaml
services:
  os:
    environment:
      # 多实例同步
      JWT_KEY_STORE_RELOAD_MS: '60000'
      # 关闭 SQLCipher，DB 已经加密
      SQLCIPHER_KEY: ''
      SQLCIPHER_ENABLED: 'false'
      # 标识 pod
      POD_ID: ${HOSTNAME}
    deploy:
      replicas: 1  # 每 OCI VM 一个实例
```

### 2.4 部署顺序

```bash
# Pod A
ssh oci-a
git clone https://github.com/wontlost-ltd/chrono-synth-deploy
cd chrono-synth-deploy/podman
cp .env.example .env  # 填入与 Pod B 相同的 JWT_KEYS_JSON
podman compose up -d

# Pod B —— 必须用与 Pod A 完全相同的 JWT_KEYS_JSON
ssh oci-b
git clone https://github.com/wontlost-ltd/chrono-synth-deploy
cd chrono-synth-deploy/podman
cp .env.example .env  # 同 Pod A
podman compose up -d

# OCI LB 健康检查路径
# /healthz   — round-robin
# /readyz    — 用于 LB 摘除未就绪实例
```

### 2.5 验证多实例同步（对应 OCI-02 / OCI-05）

```bash
# 1. 两 pod JWKS 一致
curl -s https://pod-a.beta.example.com/.well-known/jwks.json | jq -S '.keys | sort_by(.kid)' > /tmp/a.json
curl -s https://pod-b.beta.example.com/.well-known/jwks.json | jq -S '.keys | sort_by(.kid)' > /tmp/b.json
diff /tmp/a.json /tmp/b.json   # 应无差异

# 2. 在 A 上 rotate，等 60s，验证 B 已同步
ACCESS_TOKEN=$(curl -s -X POST https://pod-a.beta.example.com/api/v1/auth/login \
  -d '{"email":"admin@example.test","password":"<填>"}' | jq -r '.data.accessToken')

curl -X POST https://pod-a.beta.example.com/api/v1/auth/keys/rotate \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -d '{"newActiveKid":"kid-beta-2"}'   # 期待 200

sleep 65

# 在 B 上签 token
TOKEN_B=$(curl -s -X POST https://pod-b.beta.example.com/api/v1/auth/login ... | jq -r '...')
echo $TOKEN_B | cut -d. -f1 | base64 -d 2>/dev/null
# 期待：{"alg":"RS256","typ":"JWT","kid":"kid-beta-2"}
```

---

## 3. 通用：必备的 KMS 测试存根

**内测期间**如果还没有正式 KMS，可以用以下 Node.js HTTP 存根模拟（HMAC-SHA256，仅供内测）：

```js
// kms-stub.js — 仅内测；GA 必须接入真实 KMS
import { createServer } from 'node:http';
import { createHmac } from 'node:crypto';

const KEY = Buffer.from(process.env.KMS_STUB_KEY ?? 'beta-stub-key-do-not-use-in-prod');

createServer((req, res) => {
  if (req.url?.endsWith(':sign')) {
    const chunks = [];
    req.on('data', c => chunks.push(c));
    req.on('end', () => {
      const payload = Buffer.concat(chunks);
      const sig = createHmac('sha256', KEY).update(payload).digest('base64');
      res.writeHead(200, { 'content-type': 'application/json' });
      res.end(JSON.stringify({ keyId: 'beta-stub-key', signature: sig, alg: 'HMAC-SHA256' }));
    });
    return;
  }
  res.writeHead(404).end();
}).listen(8443, () => console.log('KMS stub on :8443'));
```

### 3.1 故意触发 KMS 失败（验证 NAS-04 / OCI-03）

把 `AUDIT_KMS_ENDPOINT` 临时指向不可达地址（如 `https://localhost:1`），等 60s 观察 `audit_chain_anchor_failures`：

```sql
SELECT tenant_id, error_code, error_message, attempted_at, recovered_at
  FROM audit_chain_anchor_failures
 ORDER BY attempted_at DESC LIMIT 10;
```

预期：错误码应是 `network` 或 `timeout`；恢复 endpoint 后 60s 内 `recovered_at` 被填充。

---

## 4. 回滚预案

| 故障 | 回滚步骤 |
|------|----------|
| JWT 轮换后两 pod 不同步 | `docker compose restart os`（reload from DB）→ 仍不同步则手动把 DB `jwt_signing_keys.state` 回滚到上一份 |
| 锚定服务持续失败 | 关 feature flag：`FEATURE_FLAG_AUDIT_KMS_SIGN_CHAIN_TAIL=false`；锚定停写，已有数据保留 |
| Web 启动后 `/conflicts` 502 | 检查 NAS 后端是否 healthy；浏览器看 Network 应是 500，不是 corrupt 数据 |
| 内测发现严重 bug | `docker compose down` → 把 compose 的 `:beta-latest` 改回前一个绿色 tag 重启 |

---

## 5. 数据备份

每 6 小时执行一次（建议 cron）：

```bash
# Postgres
docker compose exec postgres pg_dump -U chrono chrono | gzip > /volume1/backup/chrono-$(date +%Y%m%dT%H%M).sql.gz

# JWT keyRing 单独备份（应急还原密钥用）
docker compose exec postgres psql -U chrono -t -c "SELECT row_to_json(t) FROM jwt_signing_keys t" \
  | gzip > /volume1/backup/jwt-keys-$(date +%Y%m%dT%H%M).json.gz
```

恢复检查：

```bash
# 在恢复后的实例上跑
npm run audit:restore-check
# 期待：ok: true, issues: []
```

---

## 6. 监控指标白名单（dashboard 必读）

| 指标 | 阈值 | 含义 |
|------|------|------|
| `up{job="chrono-os"}` | == 1 | 服务存活 |
| `audit_chain_anchor_failures_open_total` | == 0 | 锚定失败已自愈 |
| `jwt_active_kid{pod="..."}` | 各 pod 一致 | 多实例 keyRing 已同步 |
| `feature_flag_sse_connection_count` | < 10 × CPU | SSE 连接未拥塞 |
| `http_request_duration_seconds{quantile="0.99"}` | < 0.5s | P99 延迟正常 |

---

## 7. 内测期联系人

- 紧急 Critical：直接停测，回到主 AI 协调
- 每日日志：`internal-beta-checklist.md` 同目录 `daily-beta-log.md`
- 内测结束报告：`internal-beta-report.md`（决定是否 GA）

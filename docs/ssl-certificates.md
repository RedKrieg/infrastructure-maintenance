# Shared SSL Certificates, Line of Succession & Failover

Requesting SSL certificates independently from multiple frontends causes **Let's Encrypt rate-limit bans** (5 duplicate certs/week) and causes **HTTP-01 challenge failures** when validation requests hit a proxy other than the one requesting the cert.

This suite solves this using a **Rank-Based Line of Succession + Self-Healing Cluster Mesh**.

---

## 1. Unified Challenge Forwarding with Succession

- `proxy-01` (`groups['proxies'][0]`) is the designated **Primary Certificate Node**.
- On **all** proxies, HAProxy routes `path_beg /.well-known/acme-challenge/` to `backend be_acme`.
- `be_acme` lists all cluster proxies in rank order:
  - Primary (`proxy-01`) is active.
  - Replicas (`proxy-02`, `proxy-03`) are configured with `backup`.
- **Result**: Whether Let's Encrypt hits `proxy-01`, `proxy-02`, or `proxy-03`, challenges route directly to the active certificate requester in succession order.

```
                           Let's Encrypt ACME Server
                                      │
                                      ▼
                        Layer 4 Ingress Load Balancer
                                      │
                 ┌────────────────────┼────────────────────┐
                 ▼                    ▼                    ▼
          ┌──────────────┐     ┌──────────────┐     ┌──────────────┐
          │   proxy-01   │     │   proxy-02   │     │   proxy-03   │
          │  (Primary)   │     │  (Standby)   │     │  (Standby)   │
          └──────┬───────┘     └──────┬───────┘     └──────┬───────┘
                 │                    │                    │
                 │                    │ (Routes challenge) │ (Routes challenge)
                 │                    └─────────┬──────────┘
                 │                              │
                 ▼                              ▼
      ┌────────────────────────────────────────────────────────────┐
      │         proxy-01 (or active standby in succession)         │
      │         Local acme.sh standalone challenge server          │
      └────────────────────────────────────────────────────────────┘
```

---

## 2. Multi-Directional Cluster Certificate Synchronization

- **Provisioning**: The primary proxy generates/issues certificates, and Ansible distributes the exact `.pem` bundles to all replica proxies in `/etc/haproxy/certs/`.
- **Automatic Cron Renewals**:
  - `acme.sh` renews certificates on the active node.
  - The renewal hook executes `/usr/local/bin/sync-haproxy-certs.sh`.
  - The script uses `rsync` over dedicated cluster SSH keys (`/root/.ssh/id_ed25519_certsync`) to mirror `/etc/haproxy/certs/` and `/root/.acme.sh/` to all online peer proxies, reloading HAProxy across the cluster.

---

## 3. Rank-Based Line of Succession & 1-Day Staggered Windows

What keeps `proxy-02` and `proxy-03` from trying to renew simultaneously if `proxy-01` is offline?

### 1-Day Staggered Thresholds
Standby watchdogs calculate their renewal expiration threshold staggered by **1 day per rank**:

$$\text{Threshold} = \text{acme\_fallback\_renewal\_days} - (\text{rank} - 1)$$

- `proxy-02` (Rank 1): triggers at **15 days** remaining.
- `proxy-03` (Rank 2): triggers at **14 days** remaining.
- `proxy-04` (Rank 3): triggers at **13 days** remaining.

`proxy-02` has a full 24-hour window to renew before `proxy-03` even considers checking.

### Rank Succession Reachability & Active SSH Negotiation Check
Before attempting renewal, any standby proxy queries all higher-ranking proxies (e.g., `proxy-03` checks `proxy-01` and `proxy-02`):
1. **Network Reachability**: Performs ICMP ping testing.
2. **Active Protocol Negotiation**: Verifies that the higher-ranking node's SSH service is **actively negotiating protocol exchange** (via `ssh-keyscan` key exchange and RFC 4253 banner verification).
3. If the SSH service is confirmed negotiating, the standby stands down and yields renewal authority. If SSH negotiation fails or the node is unreachable, a warning is logged and the standby proceeds in the line of succession.

### Pre-Check Cluster Reconciliation
Before testing expiration thresholds, each watchdog runs `/usr/local/bin/check-and-adopt-cluster-certs.sh`. If a peer already renewed, the local node adopts the newer certificate immediately, resetting its local certificate lifetime to 90 days.

---

## 4. Node Recovery & Automatic Rank Resumption

What happens when a higher-priority proxy (such as `proxy-01`) comes back online **after** a standby proxy renewed the certificate?

1. **Boot-Time Systemd Reconciliation Service (`haproxy-cert-reconcile.service`)**:
   - Runs `check-and-adopt-cluster-certs.sh` **before** `haproxy.service` starts.
   - Compares certificate expiration epochs (`openssl x509 -enddate`) against all peer proxies.
   - Discovers that a standby node has a newer certificate (validity difference > 1 day).
   - Copies the newer `.pem` bundle and `acme.sh` store from the peer via `rsync`.
   - HAProxy starts up with the fresh, renewed certificate.

2. **Seamless Rank Resumption**:
   - Because `proxy-01` is now online and has the renewed cert, standby watchdogs on `proxy-02` and `proxy-03` detect `proxy-01` as reachable and stand down.
   - `proxy-01` automatically resumes its rank as the primary certificate authority for future scheduled renewals.

---

## 5. Certificate Strategies: Wildcard (DNS-01) vs. Individual Endpoints (HTTP-01)

The cluster supports dual certificate issuance strategies depending on whether DNS API access is available to automate DNS TXT records.

### Strategy Comparison

| Feature | Wildcard Mode (`enable_wildcard_cert: true`) | Individual Mode (`enable_wildcard_cert: false`) |
| :--- | :--- | :--- |
| **Challenge Type** | **DNS-01** (via Cloud DNS / Route 53 / Cloudflare) | **HTTP-01** (via standalone port 8888) |
| **Certificate Scope** | Single cert covering `*.domain.com` and `domain.com` | Separate individual cert per endpoint (`app1`, `app2`) |
| **Endpoint Scaling** | Instant; new subdomains use existing wildcard cert | Requires issuing a new certificate per new endpoint |
| **Prerequisites** | Cloud DNS API access (`acme_dns_provider`) | Port 80 ingress routed to HAProxy |
| **Rate Limit Impact** | Minimal (1 certificate renewal for entire domain) | Uses 1 certificate slot per subdomain |
| **Cluster Sync** | Synced across all proxies via `sync-haproxy-certs.sh` | Synced across all proxies via `sync-haproxy-certs.sh` |

### Configuring Wildcard Certificates (DNS-01) Across Cloud Providers & Bare Metal

When DNS API access is available, wildcard certificates (`*.yourdomain.com` and `yourdomain.com`) are automatically issued and renewed via DNS-01 TXT record automation:

```yaml
# --- Google Cloud DNS (GCP) ---
enable_wildcard_cert: true
acme_dns_provider: "dns_gcloud"
acme_dns_env:
  CLOUDSDK_CORE_PROJECT: "your-gcp-project-id"
  GCP_PROJECT: "your-gcp-project-id"

# --- AWS Route 53 (AWS) ---
enable_wildcard_cert: true
acme_dns_provider: "dns_aws"
acme_dns_env:
  AWS_ACCESS_KEY_ID: "AKIA..."
  AWS_SECRET_ACCESS_KEY: "..."

# --- Azure DNS (Microsoft Azure) ---
enable_wildcard_cert: true
acme_dns_provider: "dns_azure"
acme_dns_env:
  AZURE_CLIENT_ID: "..."
  AZURE_CLIENT_SECRET: "..."
  AZURE_TENANT_ID: "..."
  AZURE_SUBSCRIPTION_ID: "..."

# --- Cloudflare (Works with Bare Metal, On-Premises, or any Cloud) ---
enable_wildcard_cert: true
acme_dns_provider: "dns_cf"
acme_dns_env:
  CF_Token: "your-cloudflare-api-token"
  CF_Account_ID: "your-cloudflare-account-id"
```

The primary proxy uses `acme.sh` with `--dns dns_gcloud` to dynamically create the required `_acme-challenge` TXT records, issues `wildcard.<domain>.pem`, and mirrors it across the proxy cluster.

### Automatic Fallback to Individual Certificates (HTTP-01)

When DNS API credentials are not available, or when running on bare-metal or private environments without DNS API control:

```yaml
enable_wildcard_cert: false
acme_dns_provider: ""
```

The automation automatically falls back to requesting individual certificates per endpoint using the HTTP-01 reverse challenge proxying described in Section 1. Both strategies utilize the exact same rank-based succession and self-healing cluster sync.

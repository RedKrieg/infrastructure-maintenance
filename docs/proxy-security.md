# Proxy Security, HTTP/2, Rate Limiting & Stats Access Control

The HAProxy frontend provides enterprise-grade performance, defense-in-depth protections, active backend health checking, and granular access control.

---

## 1. HTTP/2 Negotiation (ALPN) & Dual-Stack IPv4/IPv6

ALPN negotiation automatically serves HTTP/2 (`h2`) with transparent fallback to `http/1.1` on the HTTPS frontend (port 443). Dual-stack (`v4v6`) sockets allow frontends to receive traffic over IPv4 and IPv6 simultaneously:

```yaml
# In roles/proxy/defaults/main.yml or group_vars/proxies.yml:
haproxy_enable_http2: true
haproxy_enable_dual_stack: true
```

The TLS bind string in HAProxy configures:
```haproxy
bind :::443 v4v6 ssl crt {{ haproxy_certs_dir }}/ alpn h2,http/1.1
```

---

## 2. Security Headers & HSTS

Comprehensive response headers are automatically injected to mitigate clickjacking, MIME sniffing, and protocol downgrade attacks:

```yaml
haproxy_enable_security_headers: true
haproxy_enable_hsts: true
haproxy_hsts_max_age: 31536000          # 1 year
haproxy_hsts_include_subdomains: true
haproxy_hsts_preload: true
haproxy_header_frame_options: "SAMEORIGIN"
haproxy_header_referrer_policy: "strict-origin-when-cross-origin"
```

Injected response headers:
- `X-Content-Type-Options: nosniff`
- `X-Frame-Options: SAMEORIGIN`
- `Referrer-Policy: strict-origin-when-cross-origin`
- `Strict-Transport-Security: max-age=31536000; includeSubDomains; preload`

---

## 3. Layer 4/7 Volumetric, Connection & Slowloris Rate Limiting

Multi-metric in-memory stick-table tracking across both `fe_http` (port `80`) and `fe_https` (port `443`), paired with tight HTTP header/keep-alive timeouts and a dedicated TCP stick-table on Teleport SSH proxy port `3023`, protects against volumetric floods, Slowloris slow-header attacks, brute-force scanning, and connection exhaustion:

```yaml
# Slowloris & HTTP timeouts (HAProxy defaults)
haproxy_timeout_http_request: "10s"
haproxy_timeout_http_keep_alive: "10s"

# Web Ingress Stick-Table Limits (Ports 80 & 443 shared)
haproxy_enable_rate_limit: true
haproxy_rate_limit_table_size: "100k"   # Max distinct IPs tracked in RAM
haproxy_rate_limit_expire: "30s"        # Inactive table entry expiration
haproxy_rate_limit_period: "10s"        # Rate measurement sliding window
haproxy_rate_limit_req_rate: 300        # Max HTTP requests per IP in window
haproxy_rate_limit_err_rate: 50         # Max HTTP 4xx error responses per IP in window
haproxy_rate_limit_conn_rate: 100       # Max new TCP/TLS connections per IP in window
haproxy_rate_limit_conn_cur: 100        # Max concurrent TCP connections per IP
haproxy_rate_limit_status: 429          # HTTP 429 Too Many Requests

# Teleport SSH Proxy (Port 3023 TCP) & Host SSH (Port 22 UFW)
haproxy_ssh_proxy_conn_rate: 30         # Max new Teleport SSH connections per IP / 10s (3/sec)
haproxy_ssh_proxy_conn_cur: 50          # Max concurrent Teleport SSH sessions per IP
ssh_rate_limit_per_second: 3            # External host SSH new conn limit (internal RFC1918 exempt)
ssh_rate_limit_burst: 15
```

HAProxy multi-metric stick-table implementation:
```haproxy
stick-table type ip size 100k expire 30s store http_req_rate(10s),http_err_rate(10s),conn_rate(10s),conn_cur
tcp-request connection track-sc0 src
tcp-request connection reject if { sc_conn_rate(0) gt 100 }
tcp-request connection reject if { sc_conn_cur(0) gt 100 }
http-request deny deny_status 429 if { sc_http_req_rate(0) gt 300 }
http-request deny deny_status 429 if { sc_http_err_rate(0) gt 50 }
```

---

## 4. HTTP Backend Health Checks

Backend webservers are actively health checked using real HTTP requests with domain-specific `Host` headers rather than simple TCP handshakes:

```yaml
haproxy_backend_http_check: true
haproxy_check_inter: "3s"               # Health check interval
haproxy_check_fall: 3                   # Consecutive failures to mark down
haproxy_check_rise: 2                   # Consecutive successes to mark healthy
```

HAProxy configuration:
```haproxy
option httpchk
http-check send meth GET uri / hdr Host {{ item.external_fqdn }}
http-check expect rstatus (2..|3..)
```
HAProxy sends `GET / HTTP/1.1\r\nHost: <external_fqdn>` and expects a valid `2xx` or `3xx` response before routing visitor traffic to the backend.

---

## 5. HAProxy Stats & Prometheus Access Control (IP, CIDR & Dynamic FQDNs)

Access to the HAProxy statistics monitoring endpoint (port `8404`, URI `/stats`) and Prometheus metrics endpoint (`/metrics`) is restricted to authorized client sources supporting **plain IPv4/IPv6 addresses, CIDR blocks, and dynamic FQDN hostnames**.

> [!NOTE]
> **Single Source of Truth (SSOT)**: By default, `haproxy_stats_allowed_ips` dynamically inherits from `admin_trusted_cidrs` (e.g. in `vars/gcp_config.yml`), ensuring a single unified list secures the GCP firewall, HAProxy stats, Teleport, Grafana, and Prometheus.

```yaml
# In vars/gcp_config.yml (as SSOT):
admin_trusted_cidrs:
  - "149.154.37.115/32"       # Admin workstation public IP
  - "10.0.0.0/8"
  - "172.16.0.0/12"
  - "192.168.0.0/16"
  - "127.0.0.1"

# Or override specifically in group_vars/proxies.yml:
haproxy_stats_allowed_ips: "{{ admin_trusted_cidrs }}"

# Optional settings:
haproxy_stats_deny_action: "403"          # '403' (HTTP 403 Forbidden) or 'silent-drop' (TCP drop)
haproxy_stats_dns_refresh_minutes: 5      # Background DNS refresh frequency (default: 5 min)
```

### How FQDN Support Works
1. **Zero Request-Time Latency**: HAProxy evaluates client source IPs using an in-memory Radix tree (`acl is_allowed_stats src -f /etc/haproxy/stats_whitelist.lst`). No blocking DNS queries occur during HTTP requests.
2. **Strict Evaluation Ordering**: The whitelist ACL deny rule is evaluated **before** service delegation (such as `use-service prometheus-exporter`), ensuring that unauthorized clients attempting to access `/metrics` or `/stats` are blocked immediately.
3. **Dynamic Background DNS Refresh**: A dedicated systemd timer (`haproxy-stats-whitelist.timer`) executes `/usr/local/bin/update-haproxy-stats-whitelist.sh` every 5 minutes. If an administrator's Dynamic DNS IP changes, the script re-resolves the FQDN and updates HAProxy in real time via the runtime admin socket (`/run/haproxy/admin.sock`) without restarting the service or interrupting connections.
4. **DNS Outage Resiliency**: If external DNS fails temporarily, existing resolved IP addresses in `/etc/haproxy/stats_whitelist.lst` are preserved, preventing accidental administrative lockouts.
5. **Deny Actions**: Choose between standard HTTP `403 Forbidden` or `silent-drop` (silently drops unauthorized TCP connection attempts, appearing completely closed to port scanners).

---

## 6. Automated Log Rotation (60-Day Retention)

Cluster logs generated by certificate sync, standby fallback watchdogs, reconciliation, and ACL whitelist updaters are managed via `/etc/logrotate.d/haproxy-cluster-scripts`:
- **Targets**: `/var/log/haproxy-*.log` and `/var/log/acme-*.log`
- **Frequency**: Daily rotation, compressed, with **60-day retention** (`copytruncate`).
- **System Logs**: `systemd-journald` disk usage is capped with `MaxRetentionSec=60day`.

---

## 7. Coraza Web Application Firewall (WAF)

HAProxy integrates with [Coraza WAF](waf-coraza.md) via SPOE to inspect incoming HTTP requests for OWASP Top 10 vulnerabilities (SQLi, XSS, Path Traversal, and RCE). For full details and tuning, see the [Coraza WAF Integration Guide](waf-coraza.md).

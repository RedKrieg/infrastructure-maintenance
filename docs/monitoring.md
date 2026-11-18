# Prometheus Monitoring & Native Metrics Exporter

The suite provides native Prometheus metric scraping and an optional standalone Prometheus monitoring server with end-to-end access control.

---

## 1. HAProxy Native Prometheus Exporter

HAProxy includes a built-in Prometheus metric export engine configured on port `8404` at URI `/metrics`:

- **Unified Access Control**: Protected by the **exact same ACL IP/CIDR/FQDN whitelist and HTTP basic authentication** as the HAProxy statistics interface.
- **Automated Host Whitelisting**: Hosts defined in the `[monitoring]` inventory group are **automatically whitelisted** on all proxies without manual IP configuration.
- **Credential Generation**: Scrape authentication credentials are created directly from the central `admin_users` list (in `group_vars/all/admin_users.yml`).
- **Configuration**:
  ```haproxy
  frontend fe_stats
      bind *:8404
      acl is_allowed_stats src -f /etc/haproxy/stats_whitelist.lst
      http-request deny deny_status 403 unless is_allowed_stats
      
      # Basic Auth
      acl auth_stats http_auth(stats_users)
      http-request auth realm "HAProxy Cluster Statistics" unless auth_stats
      
      # Metrics Endpoint
      http-request use-service prometheus-exporter if { path /metrics }
      stats enable
      stats uri /stats
  ```

---

## 2. Prometheus Server Role (`roles/prometheus_server`)

The `prometheus_server` role provisions a dedicated Prometheus monitoring node on Ubuntu:

### Features
1. **Automated Inventory Target Discovery**:
   Dynamically iterates over `groups['proxies']` to generate scrape job definitions:
   ```yaml
   # Generated prometheus.yml scrape config
   scrape_configs:
     - job_name: 'haproxy_cluster'
       metrics_path: '/metrics'
       scheme: 'http'
       basic_auth:
         username: '{{ admin_users[0].name }}'
         password: '{{ admin_users[0].password }}'
       static_configs:
         - targets:
           {% for proxy in groups['proxies'] %}
           - '{{ hostvars[proxy].ansible_host }}:8404'
           {% endfor %}
   ```
2. **Config Validation with `promtool`**:
   Ansible validates the generated configuration file via `promtool check config` before reloading or restarting the `prometheus` daemon, preventing syntax errors from causing monitoring downtime.
3. **60-Day TSDB Retention**:
   Configured in `/etc/default/prometheus` via command-line flag:
   ```bash
   ARGS="--storage.tsdb.retention.time=60d"
   ```
4. **Zero-Trust Telemetry Scraping (`enable_internal_tls: true`)**:
   When zero-trust internal TLS is enabled, Node Exporter instances on all nodes bind HTTPS using their node certificates (`/etc/ssl/internal/server.crt`), and Prometheus scrapes over `scheme: https` strictly verifying each node against the Cluster Internal CA (`/etc/ssl/certs/internal-ca.crt`).
5. **Firewall Isolation**:
   Port `9090` is restricted in UFW to private subnets (`10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`, and `127.0.0.1`), blocking public internet access while permitting internal administrative inspection.

---

## 3. Automated Cluster Alerting Rules

Prometheus actively evaluates alerting rules defined in `/etc/prometheus/alert.rules.yml` (validated during deployment via `promtool check rules`):

| Alert Name | Condition | Severity | Description |
| :--- | :--- | :--- | :--- |
| **`HAProxyBackendServerDown`** | `haproxy_server_status != 1` for 1m | `critical` | Triggers immediately when a backend Nginx webserver goes offline or fails health checks. |
| **`HAProxyHigh5xxErrorRate`** | HTTP 5xx responses > 5% for 5m | `warning` | Warns if backend servers return elevated application error rates. |
| **`HAProxyRateLimitSaturationSpike`** | Denied requests > 50 in 5m | `warning` | Detects volumetric spikes or DDoS attacks triggering the 300 req/10s rate limiter. |
| **`ClusterNodeUnreachable`** | `up == 0` for 2m | `critical` | Fires when Prometheus is unable to scrape any cluster node for more than 2 minutes. |

---

## 4. Hardware Telemetry & Grafana Dashboards

- **Node Exporter**: Every cluster node runs `node_exporter` on port `9100`, providing hardware, memory, disk, and network metrics.
- **Grafana Server**: Running on port `3000` with pre-provisioned dashboards for HAProxy & Coraza WAF Overview and Fleet Hardware Health.
- For complete setup and dashboard details, refer to [grafana-dashboards.md](grafana-dashboards.md).

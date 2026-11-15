# Prometheus Monitoring & Native Metrics Exporter

The suite provides native Prometheus metric scraping and an optional standalone Prometheus monitoring server with end-to-end access control.

---

## 1. HAProxy Native Prometheus Exporter

HAProxy includes a built-in Prometheus metric export engine configured on port `8404` at URI `/metrics`:

- **Unified Access Control**: Protected by the **exact same ACL IP/CIDR/FQDN whitelist and HTTP basic authentication** as the HAProxy statistics interface.
- **Automated Host Whitelisting**: Hosts defined in the `[monitoring]` inventory group are **automatically whitelisted** on all proxies without manual IP configuration.
- **Credential Generation**: Scrape authentication credentials are created directly from the central `admin_users` list (in `vars/admin_users.yml`).
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
4. **Firewall Isolation**:
   Port `9090` is restricted in UFW to private subnets (`10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`, and `127.0.0.1`), blocking public internet access while permitting internal administrative inspection.

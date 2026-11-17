# Automated Verification & Security Smoke Testing

## Overview

The `verify_cluster.yml` playbook automates post-deployment validation across the entire cluster. It performs non-destructive smoke tests, security assertion checks, and compliance verification across edge proxies, webservers, Teleport access, and monitoring components.

---

## What Gets Verified?

The verification suite evaluates eight critical operational criteria:

1. **System Health & Security Baseline**:
   - Host uptime and reachable network connectivity.
   - UFW firewall status is active on all hosts.
   - `node_exporter` is active and publishing metrics on port `9100`.

2. **Edge Proxy Routing & Redundancy**:
   - HAProxy service is active with clean configuration syntax (`haproxy -c`).
   - Keepalived VRRP service status (when bare metal HA is enabled).
   - Ingress HTTP port 80 requests return HTTP 301 / 302 redirects to HTTPS.
   - Unrecognized Host headers trigger the default 404 catch-all backend.

3. **Web Application Firewall (Coraza WAF) Assertion**:
   - Submits synthetic SQL injection payloads (e.g. `/?test=' OR 1=1--`).
   - Verifies the Coraza WAF intercepts and blocks the attack.

4. **Telemetry & Metrics Ingestion**:
   - HAProxy stats endpoint returns HTTP 200 with valid Prometheus metrics.
   - Prometheus server health check (`/-/healthy`) returns HTTP 200.
   - Grafana API health check (`/api/health`) reports database status `"ok"`.

5. **Backend Webservers & TLS Transit**:
   - Nginx configuration syntax validity (`nginx -t`).
   - Webserver HTTP/HTTPS response validation on port 80 / 443.

6. **Teleport Zero-Trust Access**:
   - Teleport auth/proxy service state.
   - Diagnostic validation via `tctl status`.
   - Node membership registration check (`tctl nodes ls`).

7. **Database Tier & Connection Pooling**:
   - Database service status (PostgreSQL or MySQL active and enabled).
   - Local engine responsiveness (`pg_isready` on port 5432, `mysqladmin ping`).
   - PgBouncer connection pooler state on port 6432 (when enabled).

8. **Redis In-Memory Cache Tier**:
   - `redis-server` service state.
   - PING/PONG responsiveness check using `redis-cli ping` with password authentication.

9. **RabbitMQ Message Broker Tier**:
   - `rabbitmq-server` service state.
   - Diagnostic health validation via `rabbitmq-diagnostics check_running`.
   - Management REST API alarm health endpoint (`/api/health/checks/alarms`).

10. **Rclone Disaster Recovery Integration**:
   - Live logical database dump execution (`pg_dumpall`, `mysqldump`).
   - Multi-cloud remote snapshot transfer and retention pruning.

---

## Running the Verification Playbook

Run the smoke test playbook against your inventory:

```bash
# Verify the default cluster
ansible-playbook -i inventory.ini verify_cluster.yml

# Verify an AWS, GCP, Azure, or OCI deployment
ansible-playbook -i examples/inventories/inventory.aws.ini verify_cluster.yml
```

### Expected Output
When all checks succeed, the playbook terminates with a summary banner:

```
TASK [Cluster Verification Summary : Print Verification Pass Banner] **********
ok: [localhost] => {
    "msg": [
        "==========================================================",
        "           CLUSTER COMPLIANCE VERIFICATION PASSED         ",
        "==========================================================",
        " [✓] System Uptime & UFW Security Profiles Active",
        " [✓] Node Exporter Telemetry Active on Port 9100",
        " [✓] HAProxy Edge Load Balancer & Keepalived VRRP Verified",
        " [✓] HTTP to HTTPS 301/302 Redirection & 404 Catch-All OK",
        " [✓] Coraza WAF Threat Mitigation & Stats Metrics OK",
        " [✓] Webserver Nginx & Zero-Trust Backend TLS Validated",
        " [✓] Database Tier (PostgreSQL/MySQL & PgBouncer) Health Verified",
        " [✓] Redis In-Memory Cache & Session Store Responsive",
        " [✓] RabbitMQ Message Broker & Management API Operational",
        " [✓] Teleport Zero-Trust Access Gateway & Nodes Registered",
        " [✓] Prometheus Server & Grafana Telemetry Dashboards Ready",
        "=========================================================="
    ]
}
```

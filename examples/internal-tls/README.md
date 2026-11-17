# Zero-Trust Internal TLS Example & Operational Guide

This example demonstrates how to enable end-to-end cryptographic transit between HAProxy ingress load balancers and backend Nginx webservers using the replicated lightweight Internal Certificate Authority (CA).

## Quick Start: Enabling Internal TLS

1. **Set Group Variables**:
   In `group_vars/proxies.yml`:
   ```yaml
   haproxy_backend_ssl: true
   haproxy_backend_ssl_verify: "required"
   ```

   In `group_vars/webservers.yml`:
   ```yaml
   webserver_enable_ssl: true
   ```

2. **Deploy via Main Playbook**:
   ```bash
   ansible-playbook -i inventory.ini playbook.yml
   ```

3. **Verify Deployment**:
   ```bash
   ansible-playbook -i inventory.ini verify_cluster.yml
   ```

---

## Architectural Guarantees

### 1. Simultaneous CA Renewal Prevention
To prevent multiple proxy nodes from renewing the root CA at the same time:
- **Primary Authority**: `proxy-01` (`cert_primary_host`) is the primary manager. It renews the CA at the configured threshold (30 days remaining).
- **Standby Watchdog on Replicas**: Replicas (`proxy-02`, `proxy-03`) operate in standby mode. They only attempt renewal if:
  1. The certificate enters the emergency fallback window (15 days minus rank offset: `proxy-02` = 15d, `proxy-03` = 14d).
  2. AND all higher-priority proxies are confirmed unreachable via ICMP and port 8444/SSH liveness checks.
- **Process Concurrency Lock**: Local file locking (`flock`) on `/var/lock/internal-ca-renewal.lock` prevents overlapping executions.
- **Timer Jitter**: Systemd timer includes `RandomizedDelaySec=1800` to stagger execution windows across the cluster.
- **Peer Reconciliation on Recovery**: If a replica renews the CA during a primary outage, the primary automatically detects and adopts the newer CA upon recovery via `/usr/local/bin/check-and-adopt-cluster-certs.sh`.

### 2. Idempotent, Non-Destructive Ansible Runs
Ansible plays are engineered to be strictly non-destructive on subsequent runs:
- **Root CA**: Generated on `proxy-01` only if `/etc/ssl/internal/ca/cluster-ca.crt` is missing. Existing or auto-renewed CAs are never regenerated.
- **Cluster Sync**: CA keys and certificates are slurped and distributed only to uninitialized proxies lacking CA files. Existing proxies retain their active certificates.
- **Webserver Certificates**: Initial signing via `/usr/local/bin/renew-internal-cert.sh --force` runs only if `/etc/ssl/internal/webserver.crt` does not exist. Subsequent Ansible runs skip certificate generation entirely.
- **Trust Stores**: HAProxy backend CA files are maintained from the local proxy's active CA copy.

### 3. Rank-Based Client Failover
Backend webservers execute `/usr/local/bin/renew-internal-cert.sh` daily via systemd timer:
- Inspects `/etc/ssl/internal/webserver.crt`. If remaining validity is $\le 14$ days, renewal initiates.
- Submits CSR containing full SANs to `http://<proxy-ip>:8444/sign`.
- If `proxy-01` fails to respond or reports degraded health, the client automatically falls back to `proxy-02`, then `proxy-03`.
- On successful signature, the certificate is updated, latest CA is fetched, and Nginx reloads gracefully.

---

## Verification & Manual Testing

### Test CA Signer Daemon Health
```bash
curl -s http://10.0.1.10:8444/health
# Expected output:
# {"status": "healthy", "ca_configured": true, "role": "internal_ca_signer"}
```

### Force Webserver Certificate Renewal Test
On any backend webserver:
```bash
/usr/local/bin/renew-internal-cert.sh --force
```

### Test HAProxy Strict Verification from Proxy
```bash
openssl s_client -connect 10.0.1.11:443 -CAfile /etc/haproxy/certs/internal-ca.crt -servername web1.example.com
```

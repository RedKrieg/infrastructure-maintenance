# Zero-Trust Internal TLS Encryption

## Overview

In traditional cloud and enterprise topologies, SSL termination occurs at the edge load balancer, leaving internal transit between the load balancer and backend web servers unencrypted over plaintext HTTP (port 80). 

To satisfy Zero-Trust and compliance requirements (e.g., PCI-DSS, SOC 2, HIPAA), this architecture provides seamless **Internal CA & TLS** encryption:
1. HAProxy terminates public TLS (using ACME / Let's Encrypt certificates).
2. HAProxy re-encrypts outbound traffic to upstream backend webservers over HTTPS (port 443).
3. Nginx webservers serve traffic exclusively over internal TLS using node-generated cryptographic certificates.

---

## Traffic Flow Comparison

### Plain HTTP Transit (Default)
```
[Client] ──HTTPS (443)──> [HAProxy] ──HTTP (80)──> [Nginx Webserver]
```

### Zero-Trust Internal TLS Transit
```
[Client] ──HTTPS (443)──> [HAProxy] ──HTTPS (443, SSL Re-encryption)──> [Nginx Webserver]
```

---

## Enabling Internal TLS

Internal TLS can be activated globally or per environment in `group_vars/all.yml` or `group_vars/webservers.yml`:

### 1. In `roles/proxy/defaults/main.yml` (or `group_vars/proxies.yml`):
```yaml
# Enable SSL re-encryption on upstream connections to webserver backends
haproxy_backend_ssl: true

# Verification mode: "none" for self-signed internal certs, or "required" with internal CA
haproxy_backend_ssl_verify: "none"
```

### 2. In `roles/webserver/defaults/main.yml` (or `group_vars/webservers.yml`):
```yaml
# Enable HTTPS on backend Nginx instances
webserver_enable_ssl: true
webserver_ssl_cert: "/etc/ssl/internal/webserver.crt"
webserver_ssl_key: "/etc/ssl/internal/webserver.key"
```

---

## Automated Key & Certificate Provisioning

When `webserver_enable_ssl: true`, the `webserver` role automatically:
1. Creates secure directory `/etc/ssl/internal` with `0700` permissions.
2. Generates a 4096-bit RSA private key using OpenSSL.
3. Generates a self-signed X.509 certificate with Subject Alternative Names (SAN) matching the host's inventory name, IP address, and configured `external_fqdn`.
4. Opens UFW port `443/tcp` from proxy subnets.
5. Configures Nginx virtual host with modern TLS protocols (`TLSv1.2 TLSv1.3`), high-security cipher suites, and HTTP/2 support.

---

## Verification

Verify backend TLS handshake directly from a proxy node:

```bash
# Test internal HTTPS connection to web-01
curl -kv https://10.0.1.11:443/ -H "Host: web1.example.com"
```

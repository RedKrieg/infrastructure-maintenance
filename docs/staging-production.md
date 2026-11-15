# Staging vs. Production Multi-Environment Strategy

## Overview

To ensure safe testing, staging, and validation of infrastructure updates before deploying to production, the repository supports decoupled environment hierarchies under `inventories/`:
- **`inventories/staging/`**: Pre-production tier with Let's Encrypt ACME Staging CA, shorter retention schedules, and isolated staging subnets.
- **`inventories/production/`**: Production cluster with production Let's Encrypt certificates, 60-day metrics/log retention, and strict alert routing.

---

## Environment Comparison

| Dimension | Staging (`inventories/staging/`) | Production (`inventories/production/`) |
| :--- | :--- | :--- |
| **Inventory File** | `inventories/staging/hosts.ini` | `inventories/production/hosts.ini` |
| **Domain Hierarchy** | `staging-web1.example.com` | `web1.example.com` |
| **ACME CA Endpoint** | Let's Encrypt Staging Directory (`acme_use_staging: true`) | Let's Encrypt Production Directory (`acme_use_staging: false`) |
| **Rate Limit Protection**| No risk to production quotas (unlimited staging certs) | Subject to 50 certs/week/domain |
| **Metrics Retention** | 7 days (`prometheus_retention_time: 7d`) | 60 days (`prometheus_retention_time: 60d`) |
| **Scrape Frequency** | 10 seconds (rapid feedback) | 15 seconds (production scale) |
| **Alert Notification** | `staging-alerts@example.com` | `production-alerts@example.com` + On-Call Escalation |

---

## Let's Encrypt Staging Mode

In staging and CI testing environments, requesting production Let's Encrypt certificates frequently causes API rate limiting:
- **Let's Encrypt Production Limit**: 50 certificates per registered domain per week.
- **Let's Encrypt Staging Limit**: 30,000 certificates per week with higher rate limits for failed validations.

Setting `acme_use_staging: true` instructs `acme.sh` and the fallback renewal watchdogs to append `--staging`:
```bash
acme.sh --issue -d staging-web1.example.com --standalone --httpport 8888 --staging
```
This validates ACME challenge routing, HTTP-01 token exchanges, and renewal synchronization without consuming production quotas.

---

## Deployment Commands

### Deploying to Staging:
```bash
# Verify playbook syntax with staging inventory
ansible-playbook -i inventories/staging/hosts.ini playbook.yml --syntax-check

# Provision entire staging cluster
ansible-playbook -i inventories/staging/hosts.ini playbook.yml

# Verify staging deployment
ansible-playbook -i inventories/staging/hosts.ini verify_cluster.yml
```

### Deploying to Production:
```bash
# Verify playbook syntax with production inventory
ansible-playbook -i inventories/production/hosts.ini playbook.yml --syntax-check

# Provision entire production cluster
ansible-playbook -i inventories/production/hosts.ini playbook.yml

# Verify production compliance
ansible-playbook -i inventories/production/hosts.ini verify_cluster.yml
```

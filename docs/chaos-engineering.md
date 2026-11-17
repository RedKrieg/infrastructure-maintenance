# Chaos Engineering & Resilience Drills

## Overview

High-availability and failover mechanisms (VRRP floating IPs, reverse proxy health checks, certificate renewal succession) often degrade over time if not regularly exercised. 

The `chaos_drill.yml` playbook runs automated, non-destructive failure injection drills to verify that self-healing and rerouting behaviors function under real conditions.

---

## Executed Chaos Drills

### 1. Backend Outage & Dynamic Traffic Rerouting
- **Failure Injection**: Stops `nginx` on the first backend webserver in the inventory.
- **Assertion**:
  - Polls HAProxy via `/run/haproxy/admin.sock` to verify HAProxy health checks detect the failure within `fall * inter` seconds and transition the node to `DOWN`.
  - Verifies that client requests receive a graceful response rather than hanging or resetting connections.
- **Self-Healing**: Restarts Nginx on the target backend and confirms that HAProxy detects recovery (`rise` threshold) and restores the backend to `UP`.

### 2. Bare Metal HA VRRP VIP Failover (Keepalived)
- **Failure Injection**: Identifies the primary proxy node holding the shared `keepalived_vip` and terminates `keepalived`.
- **Assertion**:
  - Measures the time required for peer backup proxies to negotiate VRRP priority and claim the VIP.
  - Confirms VIP ownership on the secondary proxy via `ip addr show`.
  - Asserts that network connectivity to the VIP remains uninterrupted.
- **Self-Healing**: Restarts Keepalived on the primary proxy and confirms non-preemptive stability.

### 3. ACME Certificate Line of Succession
- **Assertion**:
  - Audits presence and executable permissions of `/usr/local/bin/sync-haproxy-certs.sh` and `/usr/local/bin/check-ssh-cluster.sh`.
  - Verifies that replica standby proxies maintain their staggered renewal offsets (1 day per rank) and do not attempt conflicting renewals while the primary proxy is operational.

### 4. Database Connection Resiliency & Service Health
- **Assertion**:
  - Validates active query execution against PostgreSQL (`SELECT 1;`) or MySQL.
  - Performs a non-destructive service reload to test runtime configuration ingestion.
  - Confirms database daemon returns cleanly to active running state without connection starvation.

### 5. Redis In-Memory Cache Snapshot & Recovery
- **Failure Injection**: Triggers background snapshot creation (`bgsave`) followed by a graceful restart of the Redis service daemon.
- **Assertion**:
  - Measures recovery latency for Redis to bind to port 6379 and load dataset from disk.
  - Verifies authenticated `redis-cli ping` returns `PONG`.

### 6. RabbitMQ Diagnostic & Alarm Status
- **Assertion**:
  - Executes `rabbitmq-diagnostics check_running` to ensure the Erlang VM, message store, and node plugins are operational.
  - Inspects `rabbitmq-diagnostics check_alarms` to verify no memory or disk watermarks are blocking publishers.

---

## Running the Chaos Drill

Execute the drill against your cluster:

```bash
# Run against active cluster inventory
ansible-playbook -i inventory.ini chaos_drill.yml

# Run against staging or production
ansible-playbook -i inventories/staging/hosts.ini chaos_drill.yml
ansible-playbook -i inventories/production/hosts.ini chaos_drill.yml
```

### Sample Output

```
TASK [Chaos Drill Results Summary : Display Chaos Drills Passed Banner] ********
ok: [localhost] => {
    "msg": [
        "==========================================================",
        "           CHAOS & RESILIENCE DRILLS PASSED               ",
        "==========================================================",
        " [✓] Backend Outage Detection & Traffic Rerouting Verified",
        " [✓] Backend Recovery & Return-to-Pool Asserted",
        " [✓] VRRP Virtual IP Migration Handshake Validated",
        " [✓] ACME Cert Succession Watchdog & Standby Ready",
        " [✓] Database Query Responsiveness & Service Health Validated",
        " [✓] Redis Cache Snapshot & Restart Recovery Confirmed",
        " [✓] RabbitMQ Broker Diagnostics & Alarm Status Verified",
        " [✓] 100% Self-Healing Confirmed: All Services Restored",
        "=========================================================="
    ]
}
```

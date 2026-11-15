# Google Chat Integration for Alertmanager

## Overview

Google Chat spaces accept incoming notifications via **Incoming Webhooks**. However, unlike Slack, Google Chat requires payloads to follow a specific JSON structure (`{"text": "..."}` or `{"cardsV2": [...]}`). Because Prometheus Alertmanager emits its own standardized webhook payload schema, a lightweight relay or translator is positioned between Alertmanager and Google Chat.

This guide details how to integrate Alertmanager with Google Chat using the zero-dependency Python relay script provided in [`examples/alertmanager/google_chat_relay.py`](../examples/alertmanager/google_chat_relay.py) or the `calert` bridge.

---

## Architecture

```
  ┌───────────────────────┐
  │   Prometheus Server   │
  │      (Port 9090)      │
  └───────────┬───────────┘
              │ Evaluates alert rules
              ▼
  ┌───────────────────────┐
  │      Alertmanager     │
  │      (Port 9093)      │
  └───────────┬───────────┘
              │ Webhook POST (native schema)
              ▼
  ┌───────────────────────┐
  │   Google Chat Relay   │
  │  (Port 5001 / Local)  │
  └───────────┬───────────┘
              │ Translates to Google Chat Cards v2
              ▼
  ┌─────────────────────────────────────────────────────────────┐
  │ Google Chat Incoming Webhook (Google Workspace Space)       │
  │ https://chat.googleapis.com/v1/spaces/.../messages          │
  └─────────────────────────────────────────────────────────────┘
```

---

## Step 1: Create a Google Chat Webhook

1. Open **Google Chat** (or Gmail) and navigate to the Space where you want to receive alerts.
2. Click the Space name at the top to open the dropdown menu.
3. Select **Apps & integrations** (or **Manage webhooks**).
4. Click **Add webhooks**.
5. Set the webhook name (e.g., `Cluster Alertmanager`) and an avatar URL (e.g., `https://prometheus.io/assets/prometheus_logo_grey.svg`).
6. Click **Save** and copy the generated Webhook URL:
   ```
   https://chat.googleapis.com/v1/spaces/AAAAxxxxxx/messages?key=AIzaSy...&token=...
   ```

---

## Step 2: Deploy the Google Chat Relay

The repository provides [`examples/alertmanager/google_chat_relay.py`](../examples/alertmanager/google_chat_relay.py), which uses only Python 3 standard library modules—no `pip` installs or virtual environments required.

### Testing Locally
```bash
export GCHAT_WEBHOOK_URL="https://chat.googleapis.com/v1/spaces/YOUR_SPACE/messages?key=YOUR_KEY&token=YOUR_TOKEN"
python3 examples/alertmanager/google_chat_relay.py 5001
```

### Running as a Persistent Systemd Service

Deploy the relay as a systemd service on your monitoring host (`monitoring-01`):

1. Copy the script to `/usr/local/bin/google_chat_relay.py`:
   ```bash
   cp examples/alertmanager/google_chat_relay.py /usr/local/bin/google_chat_relay.py
   chmod +x /usr/local/bin/google_chat_relay.py
   ```

2. Create `/etc/systemd/system/google-chat-relay.service`:
   ```ini
   [Unit]
   Description=Prometheus Alertmanager Google Chat Webhook Relay
   After=network.target

   [Service]
   Type=simple
   User=prometheus
   Group=prometheus
   Environment="PORT=5001"
   Environment="GCHAT_WEBHOOK_URL=https://chat.googleapis.com/v1/spaces/YOUR_SPACE/messages?key=YOUR_KEY&token=YOUR_TOKEN"
   ExecStart=/usr/bin/python3 /usr/local/bin/google_chat_relay.py
   Restart=always
   RestartSec=5s

   [Install]
   WantedBy=multi-user.target
   ```

3. Enable and start the service:
   ```bash
   systemctl daemon-reload
   systemctl enable --now google-chat-relay.service
   systemctl status google-chat-relay.service
   ```

---

## Step 3: Configure Alertmanager

Update `/etc/prometheus/alertmanager.yml` on the monitoring node using the template provided in [`examples/alertmanager/alertmanager-google-chat.yml`](../examples/alertmanager/alertmanager-google-chat.yml):

```yaml
global:
  resolve_timeout: 5m

route:
  group_by: ['alertname', 'cluster', 'service']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 4h
  receiver: 'google-chat-relay'

receivers:
  - name: 'google-chat-relay'
    webhook_configs:
      - url: 'http://127.0.0.1:5001/'
        send_resolved: true
```

Reload Alertmanager:
```bash
systemctl reload prometheus-alertmanager
```

---

## Step 4: Verification & Message Format

Send a test alert from your monitoring server to verify end-to-end delivery:

```bash
curl -X POST http://127.0.0.1:5001/ -H "Content-Type: application/json" -d '{
  "status": "firing",
  "commonLabels": {
    "alertname": "TestAlert",
    "cluster": "production",
    "severity": "critical"
  },
  "commonAnnotations": {
    "summary": "Synthetic Verification Alert",
    "description": "Verifying Google Chat webhook delivery from Prometheus Alertmanager."
  },
  "alerts": [
    {
      "status": "firing",
      "labels": {
        "instance": "proxy-01:8404"
      },
      "startsAt": "2026-11-15T12:00:00Z"
    }
  ]
}'
```

### Visual Appearance in Google Chat
The relay formats alerts using **Google Chat Cards v2**:
- **Header**: `🚨 [FIRING] TestAlert` or `✅ [RESOLVED] TestAlert`
- **Subtitle**: `Cluster: production | Severity: CRITICAL`
- **Sections**: Detailed alert summary, description, and list of impacted host instances.

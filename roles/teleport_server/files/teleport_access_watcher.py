#!/usr/bin/env python3
"""Teleport Access Request Notification Watcher.

Polls local Teleport Auth state (`tctl request ls --format=json`) for pending
Just-In-Time privilege elevation requests (e.g. `tsudo` -> `elevated-sudo`)
and dispatches real-time alerts with direct Web UI approval links to Prometheus
Alertmanager (/api/v2/alerts) and optional direct Slack/Google Chat/Teams webhooks.

Uses Python 3 standard library only (no external packages required).
"""

from datetime import datetime, timezone
import html
import json
import os
import signal
import subprocess
import sys
import time
import urllib.error
import urllib.request

DEFAULT_POLL_INTERVAL = 5
ALERTMANAGER_REPOST_INTERVAL_SEC = 60
REQUEST_TIMEOUT_SEC = 10

_RUNNING = True


def _handle_signal(signum, _frame):
    """Stop the polling loop cleanly on SIGINT/SIGTERM."""
    global _RUNNING
    print(f"[*] Received signal {signum}; shutting down watcher.", flush=True)
    _RUNNING = False


def utc_now_iso():
    """Return current UTC timestamp in RFC3339 format."""
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def derive_base_web_url(public_addr):
    """Derive HTTPS Teleport Web UI base URL from teleport_public_addr."""
    addr = (public_addr or "teleport.cluster.local:443").strip().rstrip("/")
    if not addr.startswith(("http://", "https://")):
        addr = f"https://{addr}"
    if addr.endswith(":443"):
        addr = addr[:-4]
    return addr


def parse_csv_urls(raw_value):
    """Split a comma-separated environment value into normalized URLs."""
    urls = []
    for entry in (raw_value or "").split(","):
        cleaned = entry.strip().rstrip("/")
        if cleaned:
            urls.append(cleaned)
    return urls


def post_json(url, payload, label):
    """POST a JSON payload to a target HTTP(S) endpoint, logging errors non-fatally."""
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=data,
        headers={"Content-Type": "application/json; charset=UTF-8"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=REQUEST_TIMEOUT_SEC) as resp:
            resp.read()
        return True
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        print(f"[!] HTTP {exc.code} delivering to {label} ({url}): {body}", file=sys.stderr, flush=True)
    except Exception as exc:
        print(f"[!] Error delivering to {label} ({url}): {exc}", file=sys.stderr, flush=True)
    return False


def fetch_pending_requests():
    """Return a dict of {request_id: request_dict} for all PENDING Teleport access requests."""
    try:
        proc = subprocess.run(
            ["tctl", "request", "ls", "--format=json"],
            capture_output=True,
            text=True,
            timeout=15,
            check=False,
        )
    except Exception as exc:
        print(f"[!] Failed executing tctl: {exc}", file=sys.stderr, flush=True)
        return None

    if proc.returncode != 0:
        err = (proc.stderr or proc.stdout or "").strip()
        print(f"[!] tctl exited {proc.returncode}: {err}", file=sys.stderr, flush=True)
        return None

    raw = (proc.stdout or "").strip()
    if not raw or raw == "null":
        return {}

    try:
        items = json.loads(raw)
    except json.JSONDecodeError as exc:
        print(f"[!] Failed parsing tctl JSON output: {exc}", file=sys.stderr, flush=True)
        return None

    if not items:
        return {}
    if isinstance(items, dict):
        items = [items]

    pending = {}
    for item in items:
        if not isinstance(item, dict):
            continue
        spec = item.get("spec") or {}
        state = spec.get("state")
        is_pending = (
            (isinstance(state, str) and state.strip().upper() in ("PENDING", "1"))
            or state == 1
        )
        if not is_pending:
            continue
        meta = item.get("metadata") or {}
        req_id = str(meta.get("name") or "").strip()
        if req_id:
            pending[req_id] = item
    return pending


def build_request_context(req_id, item, cfg):
    """Extract normalized notification metadata for a single Teleport access request."""
    spec = item.get("spec") or {}
    user = str(spec.get("user") or "unknown")
    roles_raw = spec.get("roles") or []
    roles = ", ".join(str(r) for r in roles_raw) if isinstance(roles_raw, list) else str(roles_raw or "elevated-sudo")
    reason = str(spec.get("request_reason") or "").strip() or "No reason provided"
    created = str(spec.get("created") or "").strip() or utc_now_iso()

    approval_url = f"{cfg['base_web_url']}/web/requests/{req_id}"
    queue_url = f"{cfg['base_web_url']}/web/requests"

    return {
        "req_id": req_id,
        "user": user,
        "roles": roles or "elevated-sudo",
        "reason": reason,
        "starts_at": created,
        "approval_url": approval_url,
        "queue_url": queue_url,
    }


def build_alertmanager_alert(ctx, cfg, ends_at=None):
    """Construct an Alertmanager API v2 PostableAlert object."""
    alert = {
        "labels": {
            "alertname": "TeleportSudoAccessRequestPending",
            "cluster": cfg["cluster_name"],
            "service": "teleport",
            "severity": "warning",
            "instance": cfg["hostname"],
            "request_id": ctx["req_id"],
            "requester": ctx["user"],
            "requested_roles": ctx["roles"],
        },
        "annotations": {
            "summary": f"Teleport JIT sudo request from {ctx['user']} ({ctx['roles']})",
            "description": (
                f"User '{ctx['user']}' requested role '{ctx['roles']}'. "
                f"Reason: {ctx['reason']} — Click to review/approve in Web UI: "
                f"{ctx['approval_url']} (or CLI: tapprove {ctx['req_id']})"
            ),
            "approval_url": ctx["approval_url"],
            "queue_url": ctx["queue_url"],
            "requester": ctx["user"],
            "reason": ctx["reason"],
        },
        "startsAt": ctx["starts_at"],
        "generatorURL": ctx["approval_url"],
    }
    if ends_at:
        alert["endsAt"] = ends_at
    return alert


def send_direct_webhooks(ctx, cfg):
    """Send optional one-time notifications directly to configured chat webhooks."""
    if cfg["slack_webhook_url"]:
        slack_payload = {
            "text": (
                f":key: *Teleport Sudo Elevation Request Pending*\n"
                f"*User:* `{ctx['user']}` | *Role:* `{ctx['roles']}`\n"
                f"*Reason:* {ctx['reason']}\n"
                f"*Request ID:* `{ctx['req_id']}`\n"
                f"*Approve / Deny:* <{ctx['approval_url']}|Click to Review in Teleport Web UI> "
                f"(<{ctx['queue_url']}|All Pending Requests>)"
            )
        }
        post_json(cfg["slack_webhook_url"], slack_payload, "direct-slack")

    if cfg["gchat_webhook_url"]:
        gchat_payload = {
            "cardsV2": [
                {
                    "cardId": f"teleportReq_{ctx['req_id']}",
                    "card": {
                        "header": {
                            "title": "Teleport Sudo Request Pending",
                            "subtitle": f"Cluster: {cfg['cluster_name']} | User: {ctx['user']}",
                        },
                        "sections": [
                            {
                                "header": "Just-In-Time Elevation Details",
                                "widgets": [
                                    {"textParagraph": {"text": f"<b>Requester:</b> {html.escape(ctx['user'])}"}},
                                    {"textParagraph": {"text": f"<b>Requested Role:</b> {html.escape(ctx['roles'])}"}},
                                    {"textParagraph": {"text": f"<b>Reason:</b> {html.escape(ctx['reason'])}"}},
                                    {"textParagraph": {"text": f"<b>Request ID:</b> {html.escape(ctx['req_id'])}"}},
                                    {
                                        "buttonList": {
                                            "buttons": [
                                                {
                                                    "text": "Approve / Review in Teleport Web UI",
                                                    "onClick": {"openLink": {"url": ctx["approval_url"]}},
                                                }
                                            ]
                                        }
                                    },
                                ],
                            }
                        ],
                    },
                }
            ]
        }
        post_json(cfg["gchat_webhook_url"], gchat_payload, "direct-google-chat")

    if cfg["teams_webhook_url"]:
        teams_payload = {
            "@type": "MessageCard",
            "@context": "http://schema.org/extensions",
            "themeColor": "D97706",
            "summary": f"Teleport JIT sudo request from {ctx['user']}",
            "sections": [
                {
                    "activityTitle": f"Teleport JIT Sudo Request Pending ({cfg['cluster_name']})",
                    "facts": [
                        {"name": "Requester", "value": ctx["user"]},
                        {"name": "Requested Role", "value": ctx["roles"]},
                        {"name": "Reason", "value": ctx["reason"]},
                        {"name": "Request ID", "value": ctx["req_id"]},
                    ],
                    "markdown": True,
                }
            ],
            "potentialAction": [
                {
                    "@type": "OpenUri",
                    "name": "Approve / Review in Teleport Web UI",
                    "targets": [{"os": "default", "uri": ctx["approval_url"]}],
                }
            ],
        }
        post_json(cfg["teams_webhook_url"], teams_payload, "direct-teams")


def notify_alertmanagers(alert, cfg, action_label):
    """Post an Alertmanager API v2 alert list to each configured Alertmanager URL."""
    for base_url in cfg["alertmanager_urls"]:
        endpoint = f"{base_url}/api/v2/alerts"
        if post_json(endpoint, [alert], f"alertmanager ({action_label})"):
            print(
                f"[*] Posted {action_label} alert for request {alert['labels']['request_id']} -> {endpoint}",
                flush=True,
            )


def load_config():
    """Load watcher configuration from environment variables."""
    try:
        poll_interval = max(1, int(os.environ.get("POLL_INTERVAL", str(DEFAULT_POLL_INTERVAL))))
    except ValueError:
        poll_interval = DEFAULT_POLL_INTERVAL

    return {
        "base_web_url": derive_base_web_url(os.environ.get("TELEPORT_PUBLIC_ADDR", "teleport.cluster.local:443")),
        "cluster_name": os.environ.get("TELEPORT_CLUSTER_NAME", "teleport.cluster.local").strip() or "teleport.cluster.local",
        "hostname": os.environ.get("TELEPORT_HOSTNAME", "localhost").strip() or "localhost",
        "poll_interval": poll_interval,
        "alertmanager_urls": parse_csv_urls(os.environ.get("ALERTMANAGER_URLS", "")),
        "slack_webhook_url": os.environ.get("SLACK_WEBHOOK_URL", "").strip(),
        "gchat_webhook_url": os.environ.get("GCHAT_WEBHOOK_URL", "").strip(),
        "teams_webhook_url": os.environ.get("TEAMS_WEBHOOK_URL", "").strip(),
    }


def main():
    signal.signal(signal.SIGINT, _handle_signal)
    signal.signal(signal.SIGTERM, _handle_signal)

    cfg = load_config()
    print(
        f"[*] Teleport access watcher started (web={cfg['base_web_url']}, "
        f"alertmanagers={cfg['alertmanager_urls'] or 'none'}, poll={cfg['poll_interval']}s)",
        flush=True,
    )

    # Tracked pending requests: {req_id: {"ctx": ctx, "last_sent": float}}
    tracked = {}

    while _RUNNING:
        pending = fetch_pending_requests()
        now = time.monotonic()

        if pending is not None:
            # 1. Resolve alerts that were previously pending and are no longer pending
            resolved_ids = [rid for rid in tracked if rid not in pending]
            for rid in resolved_ids:
                ctx = tracked.pop(rid)["ctx"]
                resolved_alert = build_alertmanager_alert(ctx, cfg, ends_at=utc_now_iso())
                notify_alertmanagers(resolved_alert, cfg, "resolved")

            # 2. Dispatch new pending requests and periodically refresh firing alerts
            for rid, item in pending.items():
                if rid not in tracked:
                    ctx = build_request_context(rid, item, cfg)
                    alert = build_alertmanager_alert(ctx, cfg)
                    notify_alertmanagers(alert, cfg, "firing")
                    send_direct_webhooks(ctx, cfg)
                    tracked[rid] = {"ctx": ctx, "last_sent": now}
                elif (now - tracked[rid]["last_sent"]) >= ALERTMANAGER_REPOST_INTERVAL_SEC:
                    ctx = tracked[rid]["ctx"]
                    alert = build_alertmanager_alert(ctx, cfg)
                    notify_alertmanagers(alert, cfg, "refresh")
                    tracked[rid]["last_sent"] = now

        # Sleep in short slices for responsive shutdown
        slept = 0
        while _RUNNING and slept < cfg["poll_interval"]:
            time.sleep(1)
            slept += 1


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""
Lightweight Prometheus Alertmanager to Google Chat Webhook Relay
================================================================
Translates native Alertmanager webhook JSON payloads into Google Chat Cards v2
and delivers them to a Google Workspace Space incoming webhook.

Uses Python 3 standard library only (no pip dependencies required).

Usage:
    export GCHAT_WEBHOOK_URL="https://chat.googleapis.com/v1/spaces/SPACE/messages?key=KEY&token=TOKEN"
    python3 google_chat_relay.py [PORT]
"""

import html
import json
import os
import sys
import urllib.request
import urllib.error
from http.server import HTTPServer, BaseHTTPRequestHandler

DEFAULT_PORT = 5001
GCHAT_WEBHOOK_URL = os.environ.get("GCHAT_WEBHOOK_URL", "")


def format_google_chat_card(alert_data):
    """Format Alertmanager payload into Google Chat Cards v2 format."""
    status = alert_data.get("status", "unknown").upper()
    common_labels = alert_data.get("commonLabels", {})
    common_annotations = alert_data.get("commonAnnotations", {})
    alerts = alert_data.get("alerts", [])

    is_firing = status == "FIRING"
    header_title = f"{'🚨 [FIRING]' if is_firing else '✅ [RESOLVED]'} {common_labels.get('alertname', 'Cluster Alert')}"
    header_subtitle = f"Cluster: {common_labels.get('cluster', 'production')} | Severity: {common_labels.get('severity', 'warning').upper()}"

    widgets = []

    if common_annotations.get("summary"):
        widgets.append({
            "textParagraph": {
                "text": f"<b>Summary:</b> {html.escape(str(common_annotations.get('summary')))}"
            }
        })

    if common_annotations.get("description"):
        widgets.append({
            "textParagraph": {
                "text": f"<b>Description:</b> {html.escape(str(common_annotations.get('description')))}"
            }
        })

    # Individual alert occurrences
    for alert in alerts[:5]:
        labels = alert.get("labels", {})
        instance = labels.get("instance", "unknown")
        starts_at = alert.get("startsAt", "")
        widgets.append({
            "decoratedText": {
                "topLabel": "Impacted Target",
                "text": f"<b>{html.escape(str(instance))}</b>",
                "bottomLabel": f"State: {alert.get('status', '').upper()} | Started: {starts_at[:19]}"
            }
        })

    first_alert = alerts[0] if alerts else {}
    first_annotations = first_alert.get("annotations", {})
    approval_url = (
        common_annotations.get("approval_url")
        or first_annotations.get("approval_url")
        or (
            first_alert.get("generatorURL")
            if common_labels.get("alertname") == "TeleportSudoAccessRequestPending"
            else None
        )
    )
    if approval_url:
        widgets.append({
            "buttonList": {
                "buttons": [
                    {
                        "text": "Approve / Review in Teleport Web UI",
                        "onClick": {
                            "openLink": {
                                "url": approval_url
                            }
                        }
                    }
                ]
            }
        })

    card = {
        "cardsV2": [
            {
                "cardId": "alertmanagerCard",
                "card": {
                    "header": {
                        "title": header_title,
                        "subtitle": header_subtitle,
                        "imageUrl": "https://raw.githubusercontent.com/prometheus/prometheus/main/documentation/images/prometheus-logo.svg",
                        "imageType": "CIRCLE"
                    },
                    "sections": [
                        {
                            "header": "Incident Details",
                            "collapsible": False,
                            "widgets": widgets
                        }
                    ]
                }
            }
        ]
    }
    return card


class AlertmanagerRelayHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        content_length = int(self.headers.get("Content-Length", 0))
        post_data = self.rfile.read(content_length)

        if not GCHAT_WEBHOOK_URL:
            self.send_response(500)
            self.end_headers()
            self.wfile.write(b'{"error": "GCHAT_WEBHOOK_URL environment variable is not configured."}')
            return

        try:
            alert_payload = json.loads(post_data.decode("utf-8"))
        except json.JSONDecodeError:
            self.send_response(400)
            self.end_headers()
            self.wfile.write(b'{"error": "Invalid JSON"}')
            return

        chat_message = format_google_chat_card(alert_payload)
        payload_bytes = json.dumps(chat_message).encode("utf-8")

        req = urllib.request.Request(
            GCHAT_WEBHOOK_URL,
            data=payload_bytes,
            headers={"Content-Type": "application/json; charset=UTF-8"},
            method="POST"
        )

        try:
            with urllib.request.urlopen(req, timeout=10) as response:
                resp_body = response.read()
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(b'{"status": "delivered_to_google_chat"}')
        except urllib.error.HTTPError as e:
            self.send_response(e.code)
            self.end_headers()
            self.wfile.write(e.read())
        except Exception as e:
            self.send_response(502)
            self.end_headers()
            self.wfile.write(f'{{"error": "{str(e)}"}}'.encode("utf-8"))

    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(b'{"status": "healthy", "service": "alertmanager-google-chat-relay"}')

    def log_message(self, format, *args):
        sys.stderr.write(f"[gchat-relay] {self.address_string()} - {format % args}\n")


def run(port=DEFAULT_PORT):
    server_address = ("127.0.0.1", port)
    httpd = HTTPServer(server_address, AlertmanagerRelayHandler)
    print(f"[*] Alertmanager Google Chat Relay listening on http://127.0.0.1:{port}")
    if not GCHAT_WEBHOOK_URL:
        print("[!] Warning: GCHAT_WEBHOOK_URL is not set. Outbound deliveries will fail.")
    httpd.serve_forever()


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else int(os.environ.get("PORT", DEFAULT_PORT))
    run(port)

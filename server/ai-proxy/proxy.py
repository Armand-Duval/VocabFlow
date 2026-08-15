#!/usr/bin/env python3
"""OpenAI-compatible chat proxy for KnoWell. The upstream API key never leaves this host."""

from __future__ import annotations

import json
import os
import ssl
import sys
import threading
from datetime import date, datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

LISTEN_HOST = os.environ.get("LISTEN_HOST", "127.0.0.1")
LISTEN_PORT = int(os.environ.get("LISTEN_PORT", "8787"))
APP_TOKEN = os.environ.get("APP_TOKEN", "")
UPSTREAM_BASE = os.environ.get("UPSTREAM_BASE", "https://api.deepseek.com/v1").rstrip("/")
UPSTREAM_API_KEY = os.environ.get("UPSTREAM_API_KEY", "")
UPSTREAM_MODEL = os.environ.get("UPSTREAM_MODEL", "deepseek-chat")
DAILY_LIMIT = int(os.environ.get("DAILY_LIMIT", "20"))
MAX_BODY_BYTES = int(os.environ.get("MAX_BODY_BYTES", str(256 * 1024)))
TIMEOUT_SECONDS = int(os.environ.get("TIMEOUT_SECONDS", "90"))
DATA_DIR = Path(os.environ.get("DATA_DIR", "/var/lib/knowell-ai-proxy"))

_lock = threading.Lock()
_counts: dict[str, tuple[str, int]] = {}


def _today() -> str:
    return date.today().isoformat()


def _load_counts() -> None:
    path = DATA_DIR / "ratelimit.json"
    if not path.exists():
        return
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
        if isinstance(raw, dict):
            for key, value in raw.items():
                if isinstance(value, list) and len(value) == 2:
                    _counts[key] = (str(value[0]), int(value[1]))
    except (OSError, ValueError):
        pass


def _save_counts() -> None:
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    path = DATA_DIR / "ratelimit.json"
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(_counts), encoding="utf-8")
    tmp.replace(path)


def _allow(device_id: str) -> bool:
    today = _today()
    with _lock:
        day, count = _counts.get(device_id, (today, 0))
        if day != today:
            day, count = today, 0
        if count >= DAILY_LIMIT:
            _counts[device_id] = (day, count)
            _save_counts()
            return False
        _counts[device_id] = (day, count + 1)
        _save_counts()
        return True


def _json_bytes(payload: dict, status: int = 200) -> tuple[int, bytes]:
    return status, json.dumps(payload, ensure_ascii=False).encode("utf-8")


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt: str, *args) -> None:
        sys.stderr.write("%s - %s\n" % (datetime.now(timezone.utc).isoformat(), fmt % args))

    def _send(self, status: int, body: bytes, content_type: str = "application/json") -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:
        if self.path.rstrip("/") == "/health":
            self._send(200, b'{"ok":true}')
            return
        self._send(*_json_bytes({"error": "not found"}, 404))

    def do_POST(self) -> None:
        path = self.path.split("?", 1)[0].rstrip("/")
        if path != "/v1/chat/completions":
            self._send(*_json_bytes({"error": "not found"}, 404))
            return

        if not APP_TOKEN or self.headers.get("X-KnoWell-Token") != APP_TOKEN:
            self._send(*_json_bytes({"error": "unauthorized"}, 401))
            return

        if not UPSTREAM_API_KEY:
            self._send(*_json_bytes({"error": "server missing UPSTREAM_API_KEY"}, 500))
            return

        length = int(self.headers.get("Content-Length") or "0")
        if length <= 0 or length > MAX_BODY_BYTES:
            self._send(*_json_bytes({"error": "invalid body"}, 400))
            return

        raw = self.rfile.read(length)
        try:
            payload = json.loads(raw.decode("utf-8"))
            if not isinstance(payload, dict):
                raise ValueError("body")
        except (UnicodeDecodeError, ValueError):
            self._send(*_json_bytes({"error": "invalid json"}, 400))
            return

        device = (self.headers.get("X-Device-Id") or "unknown").strip()[:80] or "unknown"
        if not _allow(device):
            self._send(*_json_bytes({"error": "今日免费次数已用完"}, 429))
            return

        payload["model"] = UPSTREAM_MODEL
        body = json.dumps(payload).encode("utf-8")
        request = Request(
            UPSTREAM_BASE + "/chat/completions",
            data=body,
            method="POST",
            headers={
                "Authorization": "Bearer " + UPSTREAM_API_KEY,
                "Content-Type": "application/json",
            },
        )
        try:
            with urlopen(request, timeout=TIMEOUT_SECONDS, context=ssl.create_default_context()) as response:
                data = response.read()
                self._send(response.status, data)
        except HTTPError as error:
            data = error.read() if error.fp else b'{"error":"upstream"}'
            self._send(error.code, data)
        except URLError:
            self._send(*_json_bytes({"error": "upstream unavailable"}, 502))


def main() -> None:
    if not APP_TOKEN:
        sys.stderr.write("APP_TOKEN is required\n")
        sys.exit(1)
    _load_counts()
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    server = ThreadingHTTPServer((LISTEN_HOST, LISTEN_PORT), Handler)
    sys.stderr.write("KnoWell AI proxy on %s:%s -> %s\n" % (LISTEN_HOST, LISTEN_PORT, UPSTREAM_BASE))
    server.serve_forever()


if __name__ == "__main__":
    main()

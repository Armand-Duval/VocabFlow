#!/usr/bin/env python3
"""OpenAI-compatible chat proxy for KnoWell. The upstream API key never leaves this host."""

from __future__ import annotations

import json
import os
import re
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
MAX_UNITS_PER_REQUEST = int(os.environ.get("MAX_UNITS_PER_REQUEST", str(DAILY_LIMIT)))
MAX_BODY_BYTES = int(os.environ.get("MAX_BODY_BYTES", str(256 * 1024)))
TIMEOUT_SECONDS = int(os.environ.get("TIMEOUT_SECONDS", "90"))
DATA_DIR = Path(os.environ.get("DATA_DIR", "/var/lib/knowell-ai-proxy"))


def _parse_device_limits(raw: str) -> dict[str, int]:
    text = (raw or "").strip()
    if not text:
        return {}
    parsed: dict[str, int] = {}
    if text.startswith("{"):
        try:
            data = json.loads(text)
        except ValueError:
            return {}
        if not isinstance(data, dict):
            return {}
        items = data.items()
    else:
        items = []
        for part in text.split(","):
            part = part.strip()
            if not part or ":" not in part:
                continue
            key, value = part.rsplit(":", 1)
            items.append((key.strip(), value.strip()))
    for key, value in items:
        device = str(key).strip()
        if not device:
            continue
        try:
            parsed[device] = max(1, int(value))
        except (TypeError, ValueError):
            continue
    return parsed


DEVICE_LIMITS = _parse_device_limits(os.environ.get("DEVICE_LIMITS", ""))


def _limit_for(device_id: str) -> int:
    return DEVICE_LIMITS.get(device_id, DAILY_LIMIT)

_VOCAB_LINE = re.compile(r"^生词[：:]\s*(.+)$", re.M)

_lock = threading.Lock()
_counts: dict[str, tuple[str, int]] = {}


def _today() -> str:
    return date.today().isoformat()


def _parse_entry(value: object) -> tuple[str, int] | None:
    if isinstance(value, list) and len(value) == 2:
        return str(value[0]), int(value[1])
    if isinstance(value, dict):
        day = value.get("date") or value.get("day")
        used = value.get("used", value.get("count"))
        if day is not None and used is not None:
            return str(day), int(used)
    return None


def _load_counts() -> None:
    path = DATA_DIR / "ratelimit.json"
    if not path.exists():
        return
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
        if not isinstance(raw, dict):
            return
        devices = raw.get("devices") if isinstance(raw.get("devices"), dict) else raw
        reserved = {"version", "limit", "devices"}
        for key, value in devices.items():
            if key in reserved:
                continue
            parsed = _parse_entry(value)
            if parsed is not None:
                _counts[str(key)] = parsed
    except (OSError, ValueError, TypeError):
        pass


def _save_counts() -> None:
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    path = DATA_DIR / "ratelimit.json"
    payload = {
        "limit": DAILY_LIMIT,
        "devices": {
            device: {"date": day, "used": count}
            for device, (day, count) in _counts.items()
        },
    }
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    tmp.replace(path)


def _quota(device_id: str) -> dict:
    today = _today()
    limit = _limit_for(device_id)
    with _lock:
        day, count = _counts.get(device_id, (today, 0))
        if day != today:
            day, count = today, 0
        remaining = max(0, limit - count)
        return {
            "date": day,
            "used": count,
            "limit": limit,
            "remaining": remaining,
        }


def _quota_headers(payload: dict) -> list[tuple[str, str]]:
    return [
        ("X-KnoWell-Limit", str(payload["limit"])),
        ("X-KnoWell-Remaining", str(payload["remaining"])),
        ("X-KnoWell-Used", str(payload["used"])),
    ]


def _count_vocab_words(payload: dict) -> int:
    messages = payload.get("messages")
    if not isinstance(messages, list):
        return 0
    for message in messages:
        if not isinstance(message, dict):
            continue
        if str(message.get("role") or "") != "user":
            continue
        content = message.get("content")
        if not isinstance(content, str):
            continue
        match = _VOCAB_LINE.search(content)
        if not match:
            continue
        raw = match.group(1).strip()
        if not raw:
            return 0
        parts = [part.strip() for part in raw.split(",")]
        return len([part for part in parts if part])
    return 0


def _header_units(headers) -> int:
    raw = headers.get("X-KnoWell-Units") or headers.get("X-Knowell-Units") or ""
    try:
        value = int(str(raw).strip())
    except (TypeError, ValueError):
        return 0
    return max(0, value)


def _units_for_request(payload: dict, headers) -> int | None:
    parsed = _count_vocab_words(payload)
    claimed = _header_units(headers)
    units = max(parsed, claimed, 1)
    if units > MAX_UNITS_PER_REQUEST:
        return None
    return units


def _reserve(device_id: str, units: int) -> bool:
    units = max(1, int(units))
    today = _today()
    limit = _limit_for(device_id)
    with _lock:
        day, count = _counts.get(device_id, (today, 0))
        if day != today:
            day, count = today, 0
        if count + units > limit:
            _counts[device_id] = (day, count)
            _save_counts()
            return False
        _counts[device_id] = (day, count + units)
        _save_counts()
        return True


def _json_bytes(payload: dict, status: int = 200) -> tuple[int, bytes]:
    return status, json.dumps(payload, ensure_ascii=False).encode("utf-8")


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt: str, *args) -> None:
        sys.stderr.write("%s - %s\n" % (datetime.now(timezone.utc).isoformat(), fmt % args))

    def _send(
        self,
        status: int,
        body: bytes,
        content_type: str = "application/json",
        extra_headers: list[tuple[str, str]] | None = None,
    ) -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        for key, value in extra_headers or []:
            self.send_header(key, value)
        self.end_headers()
        self.wfile.write(body)

    def _authorized(self) -> bool:
        return bool(APP_TOKEN) and self.headers.get("X-KnoWell-Token") == APP_TOKEN

    def _device_id(self) -> str:
        return (self.headers.get("X-Device-Id") or "unknown").strip()[:80] or "unknown"

    def do_GET(self) -> None:
        path = self.path.split("?", 1)[0].rstrip("/")
        if path == "/health":
            self._send(200, b'{"ok":true}')
            return
        if path == "/v1/quota":
            if not self._authorized():
                self._send(*_json_bytes({"error": "unauthorized"}, 401))
                return
            payload = _quota(self._device_id())
            status, body = _json_bytes(payload)
            self._send(status, body, extra_headers=_quota_headers(payload))
            return
        self._send(*_json_bytes({"error": "not found"}, 404))

    def do_POST(self) -> None:
        path = self.path.split("?", 1)[0].rstrip("/")
        if path != "/v1/chat/completions":
            self._send(*_json_bytes({"error": "not found"}, 404))
            return

        if not self._authorized():
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

        device = self._device_id()
        units = _units_for_request(payload, self.headers)
        if units is None:
            self._send(*_json_bytes({"error": "invalid units"}, 400))
            return

        if not _reserve(device, units):
            quota = _quota(device)
            message = "今日免费次数已用完" if quota["remaining"] <= 0 else "今日免费额度不足"
            body_payload = {"error": message, "needed": units, **quota}
            status, body = _json_bytes(body_payload, 429)
            self._send(status, body, extra_headers=_quota_headers(quota))
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
        quota = _quota(device)
        headers = _quota_headers(quota)
        try:
            with urlopen(request, timeout=TIMEOUT_SECONDS, context=ssl.create_default_context()) as response:
                data = response.read()
                self._send(response.status, data, extra_headers=headers)
        except HTTPError as error:
            data = error.read() if error.fp else b'{"error":"upstream"}'
            self._send(error.code, data, extra_headers=headers)
        except URLError:
            status, body = _json_bytes({"error": "upstream unavailable"}, 502)
            self._send(status, body, extra_headers=headers)


def main() -> None:
    if not APP_TOKEN:
        sys.stderr.write("APP_TOKEN is required\n")
        sys.exit(1)
    _load_counts()
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    _save_counts()
    server = ThreadingHTTPServer((LISTEN_HOST, LISTEN_PORT), Handler)
    sys.stderr.write("KnoWell AI proxy on %s:%s -> %s\n" % (LISTEN_HOST, LISTEN_PORT, UPSTREAM_BASE))
    server.serve_forever()


if __name__ == "__main__":
    main()

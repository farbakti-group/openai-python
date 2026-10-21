#!/usr/bin/env bash
#
# Sandbox-only launcher for the repository's Fieldwork dashboard (see AGENTS.md,
# "Base44 preview sandbox"). Nothing here ships with the SDK.
#
# examples/browser-use-demo is written for a local terminal: it binds 127.0.0.1, accepts
# only that origin, and gates its dashboard behind a private token it prints when it runs
# attached to a terminal. This launcher starts that example unchanged through its own
# serve() entry point and republishes it on the sandbox preview port:
#
#   GET /            -> redirect to the dashboard, carrying the run token
#   GET /dashboard   -> the dashboard, or a bootstrap that re-attaches the token after
#                       the page strips it from its own URL
#   everything else  -> Fieldwork.handle(), presented as the loopback origin it expects
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
export FIELDWORK_ROOT="$root"
cd "$root"

echo "==> Syncing SDK dependencies from uv.lock (uv sync --locked --group browser-demo)"
uv sync --locked --group browser-demo

echo "==> Starting the Fieldwork dashboard on 0.0.0.0:${PREVIEW_PORT:-3000}"
exec "${UV_PROJECT_ENVIRONMENT:-/opt/venv}/bin/python" - <<'PYTHON'
"""Publish examples/browser-use-demo on the sandbox preview entry point."""
from __future__ import annotations

import asyncio
import json
import os
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlsplit

ROOT = Path(os.environ["FIELDWORK_ROOT"]).resolve()
sys.path.insert(0, str(ROOT / "examples" / "browser-use-demo"))

from runner import Reply, failure  # noqa: E402
from server import Fieldwork, serve  # noqa: E402

PREVIEW_PORT = int(os.environ.get("PREVIEW_PORT", "3000"))
DEMO_PORT = int(os.environ.get("DEMO_PORT", "8642"))
DASHBOARD_PATH = "/dashboard"
ENTRY_PARAMETER = "preview"


def bootstrap(target: str) -> bytes:
    """One line of markup that re-attaches the token the dashboard strips from its URL."""
    page = (
        '<!doctype html><html><head><meta charset="utf-8">'
        "<title>Opening the Fieldwork dashboard…</title></head><body>"
        "Opening the Fieldwork dashboard…"
        f"<script>location.replace({json.dumps(target)})</script>"
        "</body></html>"
    )
    return page.encode("utf-8")


class PreviewGateway(BaseHTTPRequestHandler):
    """The example's own request handling, plus the preview dashboard entry point."""

    app: Fieldwork
    loop: asyncio.AbstractEventLoop

    @property
    def dashboard(self) -> str:
        return f"{DASHBOARD_PATH}?{ENTRY_PARAMETER}=1#token={self.app.token}"

    def local_reply(self) -> Reply | None:
        """Answer the two preview entry routes; None means the example owns the request."""
        url = urlsplit(self.path)
        if self.command != "GET":
            return None
        if url.path == "/":
            return Reply(302, b"", {"Location": self.dashboard})
        if url.path == DASHBOARD_PATH:
            if ENTRY_PARAMETER in parse_qs(url.query):
                return None
            return Reply(200, bootstrap(self.dashboard), {"Content-Type": "text/html; charset=utf-8"})
        return None

    def upstream_url(self) -> str:
        return "/" if urlsplit(self.path).path == DASHBOARD_PATH else self.path

    def upstream_headers(self) -> dict[str, str]:
        """Present the request as the loopback origin the example is bound to."""
        headers = {"Host": urlsplit(self.app.origin).netloc}
        token = self.headers.get("X-Demo-Token")
        if token is not None:
            headers["X-Demo-Token"] = token
        if self.headers.get("Origin") is not None:
            headers["Origin"] = self.app.origin
        return headers

    def respond(self) -> None:
        try:
            size = int(self.headers.get("Content-Length", "0"))
            if size < 0 or size > 65536:
                answer = failure(400, "The demo control request is too large.")
            else:
                data = self.rfile.read(size)
                answer = self.local_reply()
                if answer is None:
                    answer = asyncio.run_coroutine_threadsafe(
                        self.app.handle(self.command, self.upstream_url(), self.upstream_headers(), data),
                        self.loop,
                    ).result()
        except Exception:
            answer = failure(400, "Invalid demo request.")
        self.send_response(answer.status)
        for name, value in answer.headers.items():
            self.send_header(name, value)
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(answer.body)))
        self.end_headers()
        try:
            self.wfile.write(answer.body)
        except (BrokenPipeError, ConnectionResetError):
            pass

    do_GET = respond
    do_POST = respond

    def log_message(self, format: str, *args: object) -> None:
        pass


async def main() -> None:
    models = {
        name: os.environ.get(f"OPENAI_{name.upper()}_MODEL") or os.environ.get("OPENAI_MODEL")
        for name in ("responses", "decisions")
    }
    api_key = os.environ.get("OPENAI_API_KEY") or None
    async with serve(DEMO_PORT, api_key, models) as app:
        loop = asyncio.get_running_loop()
        handler = type("PreviewHandler", (PreviewGateway,), {"app": app, "loop": loop})
        server = ThreadingHTTPServer(("0.0.0.0", PREVIEW_PORT), handler)
        server.daemon_threads = True
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        print(
            f"Fieldwork dashboard: http://localhost:{PREVIEW_PORT}{DASHBOARD_PATH} "
            f"(live API {'configured' if api_key else 'not configured — Local rehearsal only'})",
            flush=True,
        )
        try:
            await asyncio.Event().wait()
        finally:
            await asyncio.to_thread(server.shutdown)
            await asyncio.to_thread(thread.join)
            server.server_close()


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        pass
PYTHON

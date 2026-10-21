"""Base44 sandbox preview entry point.

This repository is a Python SDK: it ships no web application, so there is no
product UI to serve. The sandbox preview therefore renders the SDK's own
documentation (README, api.md, helpers.md, httpx2.md, docs/) straight from the
bind-mounted checkout, so the preview always reflects the current source.

Standard library only, no SDK dependencies, read-only: it never writes to the
repository.
"""

from __future__ import annotations

import re
import html
import argparse
from pathlib import Path
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, quote

parser = argparse.ArgumentParser()
parser.add_argument("--port", type=int, default=3000)
parser.add_argument("--root", type=Path, default=Path.cwd())
args = parser.parse_args()

ROOT = args.root.resolve()
DOCUMENTS = [
    "README.md",
    "api.md",
    "helpers.md",
    "httpx2.md",
    "bedrock.md",
    "CONTRIBUTING.md",
    "AGENTS.md",
    "docs/architecture/overview.md",
    "docs/browser.md",
    "docs/realtime-translation.md",
]
PAGES = {name: ROOT / name for name in DOCUMENTS if (ROOT / name).is_file()}

LINK = re.compile(r"\[([^\]]+)\]\(([^)]+)\)")
CODE = re.compile(r"`([^`]+)`")
HEADING = re.compile(r"^(#{1,6})\s+(.*)$")
LIST = re.compile(r"^\s*[-*]\s+(.*)$")
RULE = re.compile(r"^\s*([-*_])\1{2,}\s*$")


def inline(text: str) -> str:
    text = html.escape(text, quote=False)
    text = CODE.sub(lambda m: f"<code>{m.group(1)}</code>", text)
    text = LINK.sub(lambda m: f'<a href="{html.escape(m.group(2), quote=True)}">{m.group(1)}</a>', text)
    text = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", text)
    return text


def render(markdown: str) -> str:
    out: list[str] = []
    list_open = False
    in_fence = False

    def close_list() -> None:
        nonlocal list_open
        if list_open:
            out.append("</ul>")
            list_open = False

    for line in markdown.splitlines():
        if line.startswith("```"):
            close_list()
            out.append("</pre>" if in_fence else "<pre>")
            in_fence = not in_fence
            continue
        if in_fence:
            out.append(html.escape(line))
            continue
        heading = HEADING.match(line)
        if heading:
            close_list()
            level = len(heading.group(1))
            out.append(f"<h{level}>{inline(heading.group(2))}</h{level}>")
            continue
        if RULE.match(line):
            close_list()
            out.append("<hr>")
            continue
        item = LIST.match(line)
        if item:
            if not list_open:
                out.append("<ul>")
                list_open = True
            out.append(f"<li>{inline(item.group(1))}</li>")
            continue
        if not line.strip():
            close_list()
            continue
        close_list()
        out.append(f"<p>{inline(line.strip())}</p>")
    close_list()
    if in_fence:
        out.append("</pre>")
    return "\n".join(out)


def page(title: str, body: str, current: str) -> bytes:
    nav = "\n".join(
        f'<a href="/{quote(name)}"{" class=current" if name == current else ""}>{name}</a>' for name in PAGES
    )
    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{html.escape(title)} — openai-python SDK preview</title>
<style>
  :root {{ color-scheme: light dark; }}
  body {{ margin: 0; display: flex; font: 15px/1.6 -apple-system, "Segoe UI", Roboto, sans-serif; }}
  nav {{ flex: 0 0 15rem; padding: 1.25rem 1rem; border-right: 1px solid #8884; position: sticky; top: 0; height: 100vh; overflow: auto; }}
  nav b {{ display: block; margin-bottom: .75rem; font-size: .8rem; letter-spacing: .06em; text-transform: uppercase; opacity: .65; }}
  nav a {{ display: block; padding: .25rem .4rem; border-radius: .25rem; color: inherit; text-decoration: none; font-size: .9rem; }}
  nav a:hover {{ background: #8883; }}
  nav a.current {{ background: #8883; font-weight: 600; }}
  main {{ padding: 1.5rem 2rem 4rem; max-width: 60rem; }}
  pre {{ background: #8881; padding: .75rem 1rem; border-radius: .4rem; overflow: auto; }}
  code {{ background: #8881; padding: .1rem .3rem; border-radius: .25rem; }}
  pre code {{ background: none; padding: 0; }}
  h1, h2 {{ border-bottom: 1px solid #8883; padding-bottom: .3rem; }}
  a {{ color: #0a6cff; }}
</style>
</head>
<body>
<nav><b>openai-python</b>{nav}</nav>
<main>{body}</main>
</body>
</html>""".encode()


class Handler(BaseHTTPRequestHandler):
    def do_GET(self) -> None:
        path = urlparse(self.path).path
        name = path.lstrip("/") or "README.md"
        target = PAGES.get(name)
        if target is None:
            self.send_response(404)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.end_headers()
            self.wfile.write(b"Not found. Try /README.md\n")
            return
        body = render(target.read_text(encoding="utf-8"))
        content = page(name, body, name)
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(content)))
        self.end_headers()
        self.wfile.write(content)

    def log_message(self, format: str, *arguments: object) -> None:
        pass


server = HTTPServer(("0.0.0.0", args.port), Handler)
print(f"openai-python SDK documentation preview on http://0.0.0.0:{args.port}", flush=True)
server.serve_forever()

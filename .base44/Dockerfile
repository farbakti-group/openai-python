# Base44 sandbox image for the preview environment (see AGENTS.md, "Base44 preview sandbox").
#
# Development only. This image deliberately does NOT copy the checkout: the repository
# is bind-mounted at /app and the SDK dependencies are synced from the committed
# uv.lock when the service starts, so source edits stay live. The image only carries
# what cannot live in a mounted checkout: the interpreter runtime, a pinned uv, and the
# Playwright Chromium build the repository's browser examples use.
FROM python:3.12-slim

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    UV_PROJECT_ENVIRONMENT=/opt/venv \
    UV_LINK_MODE=copy \
    PLAYWRIGHT_BROWSERS_PATH=/ms-playwright

# Keep the demo's Chromium exactly on the version the lockfile pins (playwright==1.63.0).
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl git util-linux \
    && pip install --no-cache-dir "playwright==1.63.0" \
    && playwright install --with-deps chromium \
    && rm -rf /root/.cache /var/lib/apt/lists/*

# uv is pinned to the version the repository's devcontainer and CI use.
COPY --from=ghcr.io/astral-sh/uv:0.12.5 /uv /uvx /usr/local/bin/

# Chromium's sandbox refuses to start as root, so the app runs unprivileged.
RUN useradd --create-home --uid 1000 --shell /bin/bash app \
    && mkdir -p /opt/venv /home/app/.cache/uv \
    && chown -R app:app /opt/venv /home/app

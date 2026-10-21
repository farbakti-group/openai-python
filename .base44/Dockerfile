# Base44 sandbox toolchain image for this SDK checkout.
#
# Only the *toolchain* is baked here (Node, pnpm, uv, a pinned CPython). The
# repository is bind-mounted at /app by docker-compose.base44.yml at runtime, so
# edited source is always what runs — nothing from this repo is copied in.
FROM node:22.22.3-bookworm-slim

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      git \
      curl \
      unzip \
      ca-certificates \
      python3 \
 && rm -rf /var/lib/apt/lists/*

# uv version is pinned to what CI uses (astral-sh/setup-uv).
COPY --from=ghcr.io/astral-sh/uv:0.12.5 /uv /uvx /usr/local/bin/

RUN npm install --global pnpm@11.19.0

# Pre-install the CPython that .python-version pins, into the image (not the
# bind mount) so container startups do not re-download an interpreter.
ENV UV_PYTHON_INSTALL_DIR=/usr/local/share/uv/python
RUN uv python install 3.10.16

WORKDIR /app

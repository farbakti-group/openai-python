# Repository Guidance

## Generated SDK

Most SDK source is generated from the OpenAI API schema. Follow `CONTRIBUTING.md` before
changing generated files. Handwritten policy, automation, tests, and examples
should remain small and should not alter exported SDK APIs unless the change
explicitly requires it.

## Custom-code budget

Follow [the custom-code guidance](scripts/castiron/CUSTOM_CODE.md). Budget changes
belong in a separate PR containing only `.castiron-ratchet.json`, with an explicit justification
in the PR description. Increases require a **human approving review** before merging.
Agents may investigate and draft proposals, but must not approve budget increases
(including through a human's credentials) or bypass the gate. Do not weaken
counting, broaden exclusions, or alter generation metadata to make a change pass.
The checker and effective budget come from main, not the PR. Keep default CODEOWNERS.

## Security requirements for coding agents

- Never commit real API or admin keys, bearer tokens, webhook secrets, cloud
  credentials, X.509 private keys, release credentials, or `.env` files. Read
  `OPENAI_API_KEY`, `OPENAI_ADMIN_KEY`, `OPENAI_WEBHOOK_SECRET`, and other
  credentials from the environment; use clearly fake examples and fixtures.
- Redact credentials, `Authorization` and `api-key` headers, customer data, and
  sensitive request or response bodies from logs, exceptions, snapshots, and
  test output. Clearly fake or sanitized fixtures and safe `APIError.body`
  diagnostics may remain. Preserve existing sensitive-header filtering,
  including debug logging.
- Review direct and transitive dependency changes in `pyproject.toml`, optional
  extras, dependency groups, and `uv.lock`. Check
  package provenance, build backends, and install scripts before accepting or
  running them.
- Pin third-party GitHub Actions to reviewed full commit SHAs. Minimize
  job-level token permissions and never expose secrets or write-capable tokens
  to untrusted pull-request code.
- Preserve separate build and publish jobs, protected release credentials, and
  PyPI Trusted Publishing. Grant `id-token: write` only to the trusted,
  upload-only publishing job; do not introduce long-lived PyPI tokens.
- Obtain SDK CODEOWNER review and add focused synchronous and asynchronous
  security regression tests, as applicable, for changes to authentication,
  X.509 or webhook verification, HTTP destinations, redirects, proxies, TLS,
  cloud metadata, file uploads, serialization, dependencies, GitHub Actions,
  or release workflows.
- Report suspected vulnerabilities privately as described in `SECURITY.md`;
  never disclose them in public issues, pull requests, or logs.

## Python version policy

- `requires-python` in `pyproject.toml` is the authoritative technical minimum.
- `PYTHON_VERSION_POLICY.md` is the human-readable support and release policy.
- Support every fully released, non-EOL CPython line. A documented grace period
  may temporarily add the most recently retired line.
- Keep `requires-python`, classifiers, dependency markers, README requirements,
  static-analysis targets, `.python-version`, and CI synchronized.
- Do not combine a minimum-Python change with unrelated SDK or dependency
  upgrades.

## Changing the minimum Python version

1. Update `pyproject.toml`, `.python-version`, the lock files, README,
   `CONTRIBUTING.md`, and `PYTHON_VERSION_POLICY.md`.
2. Remove dependency branches that only served the retired runtime.
3. Update minimum/current and full-matrix CI coverage.
4. Build both distributions and validate their `Requires-Python` metadata and
   old-interpreter rejection behavior.
5. Add a `## Release note` section to the pull request description naming the
   new minimum and final compatible SDK release. Do not promise security
   backports for the old release.
6. Obtain SDK CODEOWNER approval.

The deterministic Python policy check proves repository surfaces agree. It
does not decide whether an EOL grace period or floor increase is appropriate.

## Automation map

- `.github/workflows/ci.yml`
  - On pull requests and branch pushes: lint, build, metadata validation, and
    tests on the minimum and current stable Python releases.
  - Nightly and manually: smoke-tests every supported Python release and the
    allowed-failure prerelease.
- `.github/workflows/python-version-review.yml`
  - Monthly on the default branch: snapshots official CPython lifecycle data
    plus the public PyPI Python-minor distribution and asks Codex for a policy
    review.
  - Runs a pinned Codex runtime as an unprivileged user with no command network
    access and read-only repository permissions.
  - Codex cannot edit the repository or call GitHub. A separate job with no
    OpenAI credential opens or refreshes one issue only when action is needed.
  - Never changes the Python floor or merges code automatically.

## Validation

Before publishing a Python-version change, run:

```sh
uv lock
uv lock --check
./scripts/build
uv run --locked --all-extras python scripts/check-python-version-policy.py
uv run --locked --all-extras python scripts/utils/validate-python-version-wheel.py
python3.9 scripts/utils/validate-python-version-wheel.py --check-python-39
uv run --locked --all-extras python scripts/utils/validate-bedrock-wheel.py
uv run --locked --all-extras python scripts/utils/validate-httpx2-wheel.py
./scripts/lint
./scripts/test
```

Also run the scheduled compatibility matrix before release.

## Large-payload compatibility

Treat large payloads as a normal API contract, not evidence of malformed or
hostile input. Responses, Chat Completions, and other APIs can legitimately
return large `application/json` bodies and streaming events. Do not introduce
arbitrary fixed limits on bodies, events, or lines as a security or efficiency
fix. Prefer incremental processing, amortized-linear buffering, timely cleanup,
and caller cancellation. Any new rejection limit needs an explicit,
owner-approved API contract and a review of existing supported payloads and
transports.

Protect this behavior with focused, deterministic public-entrypoint tests using
large synthetic payloads generated in memory, not committed captures or live
image generation. Their high memory use is intentional: do not shrink the
payloads or raise client limits to make the tests pass. Keep coverage to the main
JSON and streaming categories, and run large cases sequentially to keep peak
memory reasonable. The fixture size is a regression probe, not a new API maximum.

## Base44 preview sandbox

`docker-compose.base44.yml` runs this repository in the Base44 preview sandbox. It is
development-only tooling: nothing under `.base44/` ships with the SDK, and none of it
changes SDK behaviour.

This repository is a library plus example scripts, so the preview entry point (host port
3000) is the repository's own browser-automation dashboard, `examples/browser-use-demo`
("Fieldwork"), started by `.base44/serve_fieldwork.sh`.

- Start / stop: `docker compose -f docker-compose.base44.yml up -d --build` /
  `docker compose -f docker-compose.base44.yml down`. Logs:
  `docker compose -f docker-compose.base44.yml logs -f demo`.
- The `demo` service builds `.base44/Dockerfile` (python:3.12-slim, pinned uv, Playwright
  Chromium). The image copies no source: the checkout is bind-mounted at `/app` and
  `uv sync --locked --group browser-demo` runs from the committed lockfile at startup, so
  `src/openai` stays editable and edits are live on the next restart.
- Verify the environment beyond the compose healthcheck (which loads the dashboard page)
  by running the example's own checks inside the container with real Chromium:

  ```sh
  docker compose -f docker-compose.base44.yml exec -T -u app demo \
    bash -lc 'cd /app && uv run --locked --group browser-demo python scripts/check-example-security.py demo'
  ```

- There is no file-watching dev server for a Python library: after editing SDK or example
  sources, restart the service
  (`docker compose -f docker-compose.base44.yml restart demo`) to pick them up.

### Sandbox-only adaptations (do not port these to the SDK)

- **Dashboard entry point.** `examples/browser-use-demo/server.py` is written for a local
  terminal: it binds `127.0.0.1`, accepts only that origin, and gates its dashboard behind
  a private token it prints when attached to a terminal. `.base44/serve_fieldwork.sh`
  imports the example's own `serve()` unchanged, adds an entry route that redirects to
  `/dashboard#token=…` with that token, and presents each request to `Fieldwork.handle()`
  as the loopback origin it expects. The example's source, CSP and origin checks are
  untouched.
- **Unprivileged app user.** The mounted checkout arrives mode `0700`, and Chromium's
  sandbox refuses to start as root; the container's command relaxes the mount to `0755`
  once at startup and then drops to the `app` user.
- **`cap_add: SYS_ADMIN`.** Chromium's own sandbox needs a user namespace, which Docker's
  default seccomp profile allows only with `CAP_SYS_ADMIN`. The sandbox stays enabled (it
  is never bypassed with `--no-sandbox`); this mirrors what CI does for the same binaries
  in `.github/scripts/setup-playwright-sandbox.sh`.
- **Live API mode** needs `OPENAI_API_KEY` from the platform secret store (delivered to
  `/run/base44/app.env`). `.env.base44-defaults` holds only the non-secret `OPENAI_MODEL`
  default and is loaded first, so a dashboard value always wins. Without a key the
  dashboard still runs Local rehearsal, which makes no API request.

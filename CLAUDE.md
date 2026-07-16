# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Purpose

This repo is a **baseline Docker image** used by multiple Python applications (e.g., hp-viz, central-wss). It provides two image variants:

| Image | Dockerfile | Requirements | Base |
|-------|-----------|--------------|------|
| `python:3.13-slim-u<N>` | `Dockerfile` | `requirements.txt` | `python:3.13-slim` (Debian) |
| `myapp:alpine` | `Dockerfile.alpine` | `requirements-alpine.txt` | `python:3.13-alpine` (musl/Alpine) |

Applications mount their source code at runtime via Docker volumes and run directly against the pre-installed image — no app code lives in this repo.

## Building

```bash
# Slim image (tag with u<N> for versioning)
docker build -t python:3.13-slim-u10 .

# Alpine image
docker build -f Dockerfile.alpine -t myapp:alpine .
```

## Vulnerability Scanning

```bash
# Scan and save results
trivy image --format json -o result.json python:3.13-slim-u10
trivy image --format json -o result.json myapp:alpine

# Quick summary
trivy image python:3.13-slim-u10
```

`result.json` in the repo root is the last scan output — it gets overwritten on each scan.

## Key Design Decisions

### Slim image CVE mitigations
- `curl`, `dnsutils`, `less` removed from the install list (not needed at runtime)
- `libgnutls30t64` explicitly upgraded to pull in the patched version
- `perl-base` force-removed via `dpkg --remove --force-remove-essential` (marked essential, but nothing runtime depends on it)
- `ncurses-bin` and `libncursesw6` removed via `apt-get remove --allow-remove-essential`
- Remaining HIGH CVEs (libtinfo6, ncurses-base) cannot be removed cleanly — readline/Python depend on them

### Alpine image package strategy
- All packages in `requirements-alpine.txt` are **unpinned** (except `xlrd==1.2.0` and minimum bounds on `jaraco.context`, `protobuf`, `wheel`)
- Reason: several packages pinned in the slim `requirements.txt` (pandas 2.1.4, gevent 24.2.1, eventlet 0.35.2) predate Python 3.13 and fail to build on Alpine
- `PyPDF2` replaced with `pypdf` (PyPDF2 is abandoned and has no musllinux wheels)
- Builder stage installs: `build-base libffi-dev openssl-dev linux-headers cargo` (cargo is for cryptography Rust extension fallback)
- Runtime stage adds: `bash libstdc++ libgcc` (bash for script compatibility; libstdc++/libgcc needed by gevent C extensions and numpy)
- `xz-libs`, `libcrypto3`, `libssl3` are upgraded via `apk upgrade` (not `apk add`) because they are pre-installed by the base image and `apk add` won't upgrade them
- `requirements-alpine.txt` is deleted inside the install `RUN` step so it doesn't land in the final image

### gunicorn + gevent + WebSocket (for consuming apps)
- Apps using Flask-SocketIO with `async_mode='gevent'` must use `worker_class = "geventwebsocket.gunicorn.workers.GeventWebSocketWorker"` — the plain `"gevent"` worker does not handle WebSocket protocol upgrades
- gunicorn 23+ dropped the eventlet worker; apps that used `worker_class = "eventlet"` must migrate to gevent
- gunicorn 21.2.0 (last with eventlet) has HIGH CVEs (CVE-2024-1135, CVE-2024-6827) — not an acceptable pin

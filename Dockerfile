# ---------- builder ----------
FROM python:3.13-slim AS builder

ENV PIP_NO_CACHE_DIR=1

# Build deps only (kept out of final image)
RUN apt-get update \
 && apt-get install -y --no-install-recommends build-essential libc6-dev \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /build
COPY requirements.txt .

# Prebuild wheels for all dependencies (outputs to /wheels)
RUN pip wheel --trusted-host pypi.org --trusted-host files.pythonhosted.org --wheel-dir /wheels -r requirements.txt


# ---------- runtime ----------
FROM python:3.13-slim

# Good Python container defaults
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

# If your app actually needs these at runtime, keep them; otherwise remove this block.
RUN apt-get update \
 && apt-get install -y --no-install-recommends curl iputils-ping \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Bring in prebuilt wheels and the requirements file
COPY --from=builder /wheels /wheels
COPY --from=builder /build/requirements.txt .

# Install strictly from the local wheels (no internet)
RUN pip install --trusted-host pypi.org --trusted-host files.pythonhosted.org --no-index --find-links=/wheels -r requirements.txt \
 && rm -rf /wheels

# Upgrade pip
RUN pip install --trusted-host pypi.org --trusted-host files.pythonhosted.org --upgrade pip


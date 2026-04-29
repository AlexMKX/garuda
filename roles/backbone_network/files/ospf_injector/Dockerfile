FROM python:3.12-slim

WORKDIR /app

RUN apt-get update \
    && apt-get install -y --no-install-recommends util-linux iproute2 curl \
    && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir "setuptools>=75.0"

# Copy pyproject.toml first; install all declared deps from it (layer cache optimization).
# Single source of truth for deps — no duplication with pyproject.toml.
COPY pyproject.toml .
RUN python3 -c \
    "import tomllib, subprocess, sys; \
     d=tomllib.load(open('pyproject.toml','rb')); \
     subprocess.check_call([sys.executable,'-m','pip','install','--no-cache-dir']+d['project']['dependencies'])"

# Copy all package source trees (sidecar_operator, frr_injector, network_manager)
COPY frr_injector/ frr_injector/
COPY sidecar_operator/ sidecar_operator/
COPY network_manager/ network_manager/

RUN pip install --no-cache-dir --no-build-isolation .

ENTRYPOINT ["python", "-m", "frr_injector.main"]

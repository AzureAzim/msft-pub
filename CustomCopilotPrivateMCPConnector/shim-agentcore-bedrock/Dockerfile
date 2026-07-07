# syntax=docker/dockerfile:1
# AgentCore MCP shim container image.
#
# This image is intentionally configuration-free: per-site config is
# injected at runtime via the SHIM_CONFIG_YAML environment variable (see
# app/config.py and docs/a2-howto-agentcore-bedrock.md, step 5), so the
# same image can be deployed unmodified to every site.

FROM python:3.12-slim AS base

# Keep Python from writing .pyc files / buffering stdout, useful in containers.
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /srv/shim

COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

COPY app ./app

# Run as a dedicated non-root user, not root.
RUN groupadd --system shim && useradd --system --gid shim --home-dir /srv/shim shim \
    && mkdir -p /var/log/mcp-shim \
    && chown -R shim:shim /srv/shim /var/log/mcp-shim
USER shim

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8080/health', timeout=3).status == 200 else 1)"

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080", "--workers", "2"]

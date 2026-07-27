# syntax=docker/dockerfile:1.7
# =============================================================================
# Multi-stage build
#
# Etapa 1 (builder): compila las dependencias a wheels. Arrastra compiladores y
#   headers que NO deben terminar en la imagen final.
# Etapa 2 (runtime): imagen slim que solo instala los wheels ya compilados.
#
# Resultado: imagen final ~90 % más chica que un build de una sola etapa, sin
# toolchain de compilación (menor superficie de ataque) y con usuario no-root.
# =============================================================================

# ------------------------------- ETAPA BUILDER -------------------------------
FROM python:3.12-slim AS builder

ENV PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /build

# build-essential se usa solo para compilar los wheels y se descarta en la
# etapa runtime (multi-stage): no viaja en la imagen final. Fijar su versión
# exacta (DL3008) no aporta seguridad y volvería frágil el build, porque esa
# versión desaparece del repo de Debian al actualizarse la imagen slim.
# hadolint ignore=DL3008
RUN apt-get update \
    && apt-get install -y --no-install-recommends build-essential \
    && rm -rf /var/lib/apt/lists/*

# Se copia solo requirements.txt primero: mientras las dependencias no cambien,
# Docker reutiliza esta capa cacheada aunque cambie el código de la app.
COPY requirements.txt .
RUN pip wheel --wheel-dir /wheels -r requirements.txt

# ------------------------------- ETAPA RUNTIME -------------------------------
FROM python:3.12-slim AS runtime

# Metadatos OCI: trazabilidad de qué commit generó qué imagen.
ARG APP_VERSION=1.0.0
ARG GIT_SHA=unknown
LABEL org.opencontainers.image.title="task-api" \
      org.opencontainers.image.version="${APP_VERSION}" \
      org.opencontainers.image.revision="${GIT_SHA}" \
      org.opencontainers.image.source="https://github.com/USUARIO/pf-devops-cloud" \
      org.opencontainers.image.licenses="MIT"

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    APP_RELEASE=${GIT_SHA}

# Usuario sin privilegios: si un atacante logra RCE, no cae como root.
RUN groupadd --system --gid 10001 appuser \
    && useradd --system --uid 10001 --gid appuser --no-create-home appuser

WORKDIR /app

COPY --from=builder /wheels /wheels
RUN pip install --no-index --find-links=/wheels /wheels/*.whl \
    && rm -rf /wheels

COPY --chown=appuser:appuser app/ ./app/

USER appuser

EXPOSE 8000

# HEALTHCHECK a nivel Docker (para docker-compose / docker run).
# En Kubernetes mandan las probes del Deployment, no esta instrucción.
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/health/live').status==200 else 1)"

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]

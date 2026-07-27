"""Métricas Prometheus de la aplicación.

Se exponen métricas de negocio y de tráfico. El endpoint /metrics es el que
Prometheus scrapea; el HPA de Kubernetes escala por CPU, pero estas métricas
permiten construir dashboards y alertas con significado real.
"""

import time
from collections.abc import Callable

from fastapi import Request, Response
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Gauge, Histogram, generate_latest

REQUEST_COUNT = Counter(
    "http_requests_total",
    "Cantidad total de requests HTTP procesados",
    ["method", "endpoint", "status_code"],
)

REQUEST_LATENCY = Histogram(
    "http_request_duration_seconds",
    "Latencia de los requests HTTP en segundos",
    ["method", "endpoint"],
    buckets=(0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0),
)

TASKS_TOTAL = Gauge(
    "tasks_total",
    "Cantidad de tareas actualmente almacenadas",
    ["status"],
)

APP_INFO = Gauge(
    "app_info",
    "Metadatos de la aplicación desplegada",
    ["version", "environment"],
)


async def metrics_middleware(request: Request, call_next: Callable) -> Response:
    """Registra latencia y conteo de cada request."""
    start = time.perf_counter()
    response = await call_next(request)
    elapsed = time.perf_counter() - start

    # Se usa la ruta declarada (/tasks/{task_id}) y no la concreta (/tasks/42)
    # para evitar explosión de cardinalidad en Prometheus.
    route = request.scope.get("route")
    endpoint = getattr(route, "path", request.url.path)

    if endpoint != "/metrics":
        REQUEST_COUNT.labels(request.method, endpoint, response.status_code).inc()
        REQUEST_LATENCY.labels(request.method, endpoint).observe(elapsed)

    response.headers["X-Process-Time-Ms"] = f"{elapsed * 1000:.2f}"
    return response


def render_metrics() -> Response:
    return Response(content=generate_latest(), media_type=CONTENT_TYPE_LATEST)

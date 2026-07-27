"""Punto de entrada de la aplicación FastAPI."""

import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI

from app import __version__
from app.config import get_settings
from app.logging_config import setup_logging
from app.metrics import APP_INFO, metrics_middleware, render_metrics
from app.routers import health, tasks

logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    settings = get_settings()
    setup_logging(settings.log_level)
    APP_INFO.labels(version=__version__, environment=settings.environment).set(1)
    logger.info(
        "Aplicación iniciada",
        extra={"path": "/", "status_code": 0},
    )
    yield
    logger.info("Aplicación detenida", extra={"path": "/", "status_code": 0})


settings = get_settings()

app = FastAPI(
    title="Task API",
    description="Aplicación de referencia del pipeline CI/CD integral.",
    version=__version__,
    lifespan=lifespan,
)

app.middleware("http")(metrics_middleware)
app.include_router(health.router)
app.include_router(tasks.router)


@app.get("/", tags=["root"])
def root() -> dict[str, str]:
    return {
        "service": settings.app_name,
        "version": __version__,
        "environment": settings.environment,
        "docs": "/docs",
        "metrics": "/metrics",
    }


@app.get("/metrics", include_in_schema=False)
def metrics():
    """Endpoint scrapeado por Prometheus."""
    return render_metrics()

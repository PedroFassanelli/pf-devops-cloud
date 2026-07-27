"""Endpoints de salud usados por las probes de Kubernetes.

- /health/live  -> livenessProbe: ¿el proceso está vivo?
- /health/ready -> readinessProbe: ¿puede recibir tráfico?

Separar ambas evita que Kubernetes reinicie un Pod que solo está calentando.
"""

from fastapi import APIRouter

from app import __version__
from app.config import get_settings
from app.models import HealthResponse

router = APIRouter(prefix="/health", tags=["health"])


@router.get("/live", response_model=HealthResponse)
def liveness() -> HealthResponse:
    settings = get_settings()
    return HealthResponse(status="alive", version=__version__, environment=settings.environment)


@router.get("/ready", response_model=HealthResponse)
def readiness() -> HealthResponse:
    settings = get_settings()
    return HealthResponse(status="ready", version=__version__, environment=settings.environment)

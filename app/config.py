"""Configuración de la aplicación.

Toda la configuración se lee de variables de entorno (12-factor app).
Nunca se hardcodean credenciales: en Kubernetes llegan vía ConfigMap/Secret.
"""

from functools import lru_cache

from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    app_name: str = "task-api"
    environment: str = "local"
    log_level: str = "INFO"
    api_key: str = "dev-local-key"
    release: str = "dev"

    model_config = {"env_prefix": "APP_", "case_sensitive": False}


@lru_cache
def get_settings() -> Settings:
    return Settings()

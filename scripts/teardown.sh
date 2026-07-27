#!/usr/bin/env bash
# =============================================================================
# Destruye el entorno local. FinOps también significa no dejar cosas
# encendidas cuando no se usan, aunque acá el recurso sea tu propia RAM.
# =============================================================================
set -euo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "Destruyendo el entorno local..."
cd "${RAIZ}/terraform/environments/local"
terraform destroy -auto-approve

echo "Limpiando imágenes locales..."
docker rmi task-api:local 2>/dev/null || true

echo "Entorno eliminado."

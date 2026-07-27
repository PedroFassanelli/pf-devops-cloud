#!/usr/bin/env bash
# =============================================================================
# Recolecta en un directorio todas las evidencias textuales que pide la
# consigna. Las capturas de pantalla se toman aparte (ver docs/EVIDENCIAS.md).
#
# Uso: ./scripts/evidencias.sh
# =============================================================================
set -euo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAMESPACE="task-api"
DESTINO="${RAIZ}/evidencias/$(date +%Y%m%d-%H%M%S)"
HOST="task-api.local"

mkdir -p "$DESTINO"
echo "Recolectando evidencias en $DESTINO"

capturar() {
  local archivo="$1"; shift
  echo "  -> $archivo"
  {
    echo "\$ $*"
    echo "----------------------------------------"
    "$@" 2>&1 || echo "(comando falló o no aplica)"
  } > "${DESTINO}/${archivo}"
}

# --- Estado del cluster ---
capturar 01-nodos.txt              kubectl get nodes -o wide
capturar 02-recursos.txt           kubectl get all -n "$NAMESPACE" -o wide
capturar 03-deployment.txt         kubectl describe deployment task-api -n "$NAMESPACE"
capturar 04-pods.txt               kubectl get pods -n "$NAMESPACE" -o wide
capturar 05-service.txt            kubectl describe service task-api -n "$NAMESPACE"
capturar 06-ingress.txt            kubectl describe ingress task-api -n "$NAMESPACE"
capturar 07-hpa.txt                kubectl describe hpa task-api -n "$NAMESPACE"
capturar 08-consumo.txt            kubectl top pods -n "$NAMESPACE"
capturar 09-eventos.txt            kubectl get events -n "$NAMESPACE" --sort-by=.lastTimestamp

# --- Logs de la aplicación (formato JSON estructurado) ---
echo "  -> 10-logs-app.txt"
kubectl logs -n "$NAMESPACE" -l app.kubernetes.io/name=task-api \
  --tail=300 --all-containers > "${DESTINO}/10-logs-app.txt" 2>&1 || true

# --- Verificación funcional a través del Ingress ---
echo "  -> 11-pruebas-funcionales.txt"
{
  echo "=== GET / ==="
  curl -s -H "Host: ${HOST}" "http://${HOST}:8080/" || true
  echo -e "\n\n=== GET /health/live ==="
  curl -s -H "Host: ${HOST}" "http://${HOST}:8080/health/live" || true
  echo -e "\n\n=== POST /api/v1/tasks ==="
  curl -s -X POST -H "Host: ${HOST}" -H 'Content-Type: application/json' \
    -d '{"title":"Evidencia de funcionamiento"}' \
    "http://${HOST}:8080/api/v1/tasks" || true
  echo -e "\n\n=== GET /api/v1/tasks ==="
  curl -s -H "Host: ${HOST}" "http://${HOST}:8080/api/v1/tasks" || true
  echo -e "\n\n=== Muestra de /metrics ==="
  curl -s -H "Host: ${HOST}" "http://${HOST}:8080/metrics" | grep -E '^(http_requests_total|tasks_total|app_info)' | head -25 || true
} > "${DESTINO}/11-pruebas-funcionales.txt" 2>&1

# --- Seguridad y configuración ---
capturar 12-securitycontext.txt    kubectl get pod -n "$NAMESPACE" -l app.kubernetes.io/name=task-api -o jsonpath='{.items[0].spec.securityContext}{"\n"}{.items[0].spec.containers[0].securityContext}'
capturar 13-recursos-asignados.txt kubectl get pods -n "$NAMESPACE" -o custom-columns='POD:.metadata.name,CPU_REQ:.spec.containers[0].resources.requests.cpu,MEM_REQ:.spec.containers[0].resources.requests.memory,CPU_LIM:.spec.containers[0].resources.limits.cpu,MEM_LIM:.spec.containers[0].resources.limits.memory'
capturar 14-monitoreo.txt          kubectl get pods,svc -n monitoring

# --- Imagen Docker ---
echo "  -> 15-imagen-docker.txt"
{
  echo "=== Tamaño de la imagen ==="
  docker images task-api --format "{{.Repository}}:{{.Tag}}  {{.Size}}" || true
  echo -e "\n=== Historial de capas ==="
  docker history task-api:local --format "{{.CreatedBy}}\t{{.Size}}" 2>/dev/null | head -20 || true
  echo -e "\n=== Usuario del contenedor (debe ser 10001, NO root) ==="
  docker run --rm --entrypoint id task-api:local 2>/dev/null || true
} > "${DESTINO}/15-imagen-docker.txt" 2>&1

echo ""
echo "Evidencias guardadas en: $DESTINO"
ls -1 "$DESTINO"
echo ""
echo "Falta capturar las pantallas: ver docs/EVIDENCIAS.md"

#!/usr/bin/env bash
# =============================================================================
# Genera carga sostenida contra la aplicación para demostrar el HPA en acción.
# Es LA evidencia del punto de auto-escalado: mostrar el HPA pasando de 2 a N
# réplicas y volviendo a bajar.
#
# Uso: ./scripts/load-test.sh [duracion_segundos] [concurrencia]
# =============================================================================
set -euo pipefail

DURACION="${1:-300}"
CONCURRENCIA="${2:-40}"
HOST="task-api.local"
URL="http://${HOST}:8080"
NAMESPACE="task-api"

echo "Generando carga durante ${DURACION}s con ${CONCURRENCIA} workers"
echo "Abrí OTRA terminal y ejecutá para ver el escalado en vivo:"
echo "    watch -n 2 'kubectl get hpa,pods -n ${NAMESPACE}'"
echo ""
read -rp "Enter para comenzar..."

echo "--- Estado inicial del HPA ---"
kubectl get hpa task-api -n "$NAMESPACE"

FIN=$(( $(date +%s) + DURACION ))
PIDS=()

for i in $(seq 1 "$CONCURRENCIA"); do
  (
    while [ "$(date +%s)" -lt "$FIN" ]; do
      curl -s -o /dev/null -H "Host: ${HOST}" "${URL}/api/v1/tasks" || true
      curl -s -o /dev/null -X POST -H "Host: ${HOST}" \
        -H 'Content-Type: application/json' \
        -d '{"title":"carga","description":"generada por load-test"}' \
        "${URL}/api/v1/tasks" || true
      curl -s -o /dev/null -H "Host: ${HOST}" "${URL}/health/ready" || true
    done
  ) &
  PIDS+=($!)
done

# Reporta el estado del HPA cada 15 segundos mientras dura la prueba.
while [ "$(date +%s)" -lt "$FIN" ]; do
  RESTA=$(( FIN - $(date +%s) ))
  printf '\n[%3ds restantes] ' "$RESTA"
  kubectl get hpa task-api -n "$NAMESPACE" --no-headers
  kubectl get pods -n "$NAMESPACE" --no-headers | wc -l | xargs echo "    Pods:"
  sleep 15
done

wait "${PIDS[@]}" 2>/dev/null || true

echo ""
echo "--- Carga finalizada ---"
kubectl get hpa task-api -n "$NAMESPACE"
kubectl get pods -n "$NAMESPACE"
echo ""
echo "El HPA tarda ~5 minutos (stabilizationWindowSeconds: 300) en volver a"
echo "reducir réplicas. Es intencional: evita el flapping."

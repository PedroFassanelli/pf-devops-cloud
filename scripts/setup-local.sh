#!/usr/bin/env bash
# =============================================================================
# Levanta el entorno local completo: cluster kind vía Terraform, imagen de la
# app, manifiestos y stack de monitoreo.
#
# Uso: ./scripts/setup-local.sh
# =============================================================================
set -euo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$RAIZ"

NAMESPACE="task-api"
CLUSTER="task-api-local"
IMAGEN="task-api:local"

info()  { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
ok()    { printf '\033[0;32m    OK: %s\033[0m\n' "$*"; }
error() { printf '\033[0;31m    ERROR: %s\033[0m\n' "$*" >&2; }

# ------------------------------ REQUISITOS -----------------------------------
info "Verificando herramientas requeridas"
FALTAN=()
for cmd in docker terraform kubectl kind helm kustomize; do
  if command -v "$cmd" >/dev/null 2>&1; then
    ok "$cmd $("$cmd" version --short 2>/dev/null | head -1 || echo '')"
  else
    FALTAN+=("$cmd")
  fi
done

if [ ${#FALTAN[@]} -gt 0 ]; then
  error "Faltan herramientas: ${FALTAN[*]}"
  echo "    Instalación: ver la sección 'Requisitos previos' del README."
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  error "Docker no está corriendo."
  exit 1
fi

# --------------------------- INFRA CON TERRAFORM -----------------------------
info "Provisionando el cluster con Terraform (tarda ~4 minutos)"
cd terraform/environments/local
terraform init -input=false
terraform apply -auto-approve
cd "$RAIZ"
ok "Cluster '$CLUSTER' listo"

kubectl cluster-info --context "kind-${CLUSTER}"

# ------------------------------ IMAGEN DE LA APP -----------------------------
info "Construyendo la imagen de la aplicación"
docker build -t "$IMAGEN" --build-arg GIT_SHA="$(git rev-parse --short HEAD 2>/dev/null || echo local)" .
docker images "$IMAGEN" --format "    Tamaño de la imagen: {{.Size}}"

info "Cargando la imagen en el cluster"
kind load docker-image "$IMAGEN" --name "$CLUSTER"
ok "Imagen disponible en los nodos"

# -------------------------------- DESPLIEGUE ---------------------------------
info "Desplegando la aplicación"
kubectl apply -f k8s/base/namespace.yaml

# El Secret se genera en el momento; su valor no vive en el repositorio.
kubectl create secret generic task-api-secret \
  --namespace "$NAMESPACE" \
  --from-literal=APP_API_KEY="${APP_API_KEY:-clave-local-$(date +%s)}" \
  --dry-run=client -o yaml | kubectl apply -f -

(cd k8s/base && kustomize edit set image "ghcr.io/USUARIO/task-api=${IMAGEN}")
kubectl apply -k k8s/base/
(cd k8s/base && kustomize edit set image "ghcr.io/USUARIO/task-api=ghcr.io/USUARIO/task-api:latest")

kubectl rollout status deployment/task-api -n "$NAMESPACE" --timeout=300s
ok "Aplicación desplegada"

# -------------------------------- MONITOREO ----------------------------------
info "Configurando el monitoreo"
# El ConfigMap task-api-dashboard lo crea Terraform antes del chart de
# monitoreo (ver terraform/environments/local/main.tf): Grafana lo monta al
# arrancar y crearlo después dejaba el Pod en ContainerCreating.
kubectl apply -f monitoring/servicemonitor.yaml
kubectl apply -f monitoring/prometheus-rules.yaml
ok "ServiceMonitor y reglas de alerta aplicados"

# --------------------------------- RESUMEN -----------------------------------
info "Entorno listo"
kubectl get deploy,pod,svc,ingress,hpa -n "$NAMESPACE"

cat <<RESUMEN

  Agregá esta línea a /etc/hosts (una sola vez):
      127.0.0.1 task-api.local

  Accesos:
      Aplicación   http://task-api.local:8080
      Swagger UI   http://task-api.local:8080/docs
      Métricas     http://task-api.local:8080/metrics

      Grafana      kubectl port-forward -n monitoring svc/monitoring-grafana 3000:80
                   -> http://localhost:3000  (admin / admin)

      Prometheus   kubectl port-forward -n monitoring svc/monitoring-kube-prometheus-prometheus 9090:9090
                   -> http://localhost:9090

  Siguiente paso:
      ./scripts/load-test.sh      genera carga y dispara el autoescalado
      ./scripts/evidencias.sh     recolecta las evidencias para el informe

RESUMEN

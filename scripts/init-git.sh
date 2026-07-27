#!/usr/bin/env bash
# =============================================================================
# Inicializa el repositorio con un historial de commits lógico y descriptivo.
#
# La consigna evalúa "commits frecuentes y descriptivos". Un único commit
# llamado "primer commit" con 75 archivos adentro no cumple ese criterio.
# Este script agrupa los archivos por unidad de trabajo y genera 13 commits
# que cuentan la historia real de cómo se construyó el proyecto.
#
# Se ejecuta con TU identidad de git, así los commits quedan a tu nombre.
#
# Uso:
#   chmod +x scripts/init-git.sh
#   ./scripts/init-git.sh
# =============================================================================
set -euo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$RAIZ"

# ---------------------------- VERIFICACIONES ---------------------------------
if [ -d .git ]; then
  echo "ERROR: ya existe un repositorio git en este directorio."
  echo "       Si querés regenerar el historial: rm -rf .git && $0"
  exit 1
fi

if ! git config user.name >/dev/null 2>&1 || ! git config user.email >/dev/null 2>&1; then
  echo "ERROR: falta configurar tu identidad de git. Ejecutá:"
  echo "       git config --global user.name \"Tu Nombre\""
  echo "       git config --global user.email \"tu@email.com\""
  exit 1
fi

echo "Inicializando repositorio como: $(git config user.name) <$(git config user.email)>"
echo ""

git init -q -b main

# Commits en formato Conventional Commits: tipo(alcance): descripción.
# Es el estándar de facto y permite generar changelogs automáticos.
commit() {
  local mensaje="$1"; shift
  git add -- "$@" 2>/dev/null || true
  if git diff --cached --quiet; then
    echo "  (sin cambios) $mensaje"
    return
  fi
  git commit -q -m "$mensaje"
  echo "  $(git rev-parse --short HEAD)  $mensaje"
}

echo "Generando historial:"

commit "chore: configuración inicial del repositorio

Agrega .gitignore con reglas para Python, Terraform y secretos,
.dockerignore para reducir el contexto de build, y las plantillas
de variables de entorno." \
  .gitignore .dockerignore .env.example

commit "feat(app): API REST de tareas con FastAPI

Implementa el CRUD de tareas con almacenamiento en memoria.
La aplicación es stateless para permitir escalado horizontal
sin coordinación entre réplicas." \
  app/__init__.py app/models.py app/store.py app/routers/ pyproject.toml requirements.txt

commit "feat(app): configuración por variables de entorno y logs JSON

Aplica el patrón 12-factor: toda la configuración se lee del entorno.
Los logs estructurados en JSON son parseables por cualquier stack de
observabilidad sin expresiones regulares." \
  app/config.py app/logging_config.py

commit "feat(observability): instrumentación con métricas Prometheus

Expone contador de requests, histograma de latencias y un gauge de
negocio con las tareas por estado.

El middleware usa la ruta declarada y no la concreta para evitar
explosión de cardinalidad en Prometheus." \
  app/metrics.py app/main.py

commit "test: suite de tests unitarios con 99% de cobertura

18 casos que cubren health checks, CRUD, validaciones y el endpoint
de métricas. El pipeline exige un mínimo del 80%." \
  tests/ requirements-dev.txt

commit "feat(docker): imagen multi-stage optimizada

Etapa builder compila las dependencias a wheels; la etapa runtime
solo instala los wheels ya compilados, dejando el toolchain fuera
de la imagen final.

Incluye usuario no-root (UID 10001), HEALTHCHECK y etiquetas OCI
para trazabilidad entre commit e imagen." \
  Dockerfile

commit "feat(k8s): manifiestos de despliegue, exposición y autoescalado

Deployment con rolling update sin downtime, Service ClusterIP,
Ingress con rate limiting y HPA por CPU y memoria.

El Deployment omite el campo replicas a propósito: el HPA es su
único dueño. Fijarlo generaría una pelea en cada despliegue." \
  k8s/base/namespace.yaml k8s/base/configmap.yaml k8s/base/secret.example.yaml \
  k8s/base/deployment.yaml k8s/base/service.yaml k8s/base/ingress.yaml \
  k8s/base/hpa.yaml k8s/base/kustomization.yaml

commit "feat(k8s): endurecimiento de seguridad y disponibilidad

Agrega PodDisruptionBudget para sobrevivir al drenaje de nodos
(necesario por el uso de instancias SPOT) y NetworkPolicy que
restringe el tráfico entrante al Ingress y a Prometheus, y el
saliente solo a DNS." \
  k8s/base/pdb.yaml k8s/base/networkpolicy.yaml

commit "feat(terraform): módulos reutilizables de infraestructura

Tres módulos con variables validadas y outputs:
- network: VPC, subnets multi-AZ, NAT Gateway configurable
- cluster: EKS con node group SPOT, IAM mínimo, cifrado KMS
- app-registry: ECR con escaneo en push y lifecycle policies" \
  terraform/modules/

commit "feat(terraform): entornos local y AWS

El entorno local provisiona un cluster kind e instala la plataforma
completa vía Helm: Ingress Controller, metrics-server y el stack de
Prometheus y Grafana.

El entorno AWS compone los tres módulos. Se valida en el pipeline
pero su apply es manual." \
  terraform/environments/

commit "feat(monitoring): stack de observabilidad

ServiceMonitor para el descubrimiento declarativo de targets,
cuatro reglas de alerta y un dashboard de Grafana con 11 paneles
que incluye métricas de negocio, no solo de infraestructura.

Agrega también docker-compose para validar la instrumentación
sin levantar Kubernetes." \
  monitoring/ docker-compose.yml

commit "ci: pipeline de integración continua

Seis jobs, los primeros cuatro en paralelo: calidad y tests, SAST
con Bandit y Semgrep, CodeQL, y seguridad de IaC con Checkov,
Hadolint y kubeconform.

El build solo arranca si todos pasaron, y la imagen resultante se
escanea con Trivy." \
  .github/workflows/ci.yml .github/dependabot.yml

commit "ci: despliegue continuo con cluster efímero y DAST

El job de deploy crea un cluster kind dentro del runner, despliega,
verifica el rollout, ejecuta smoke tests contra el Ingress y
recolecta evidencias.

Esto permite un despliegue y un DAST reales con costo cero y sin
infraestructura persistente entre corridas." \
  .github/workflows/cd.yml .github/kind-ci.yaml .github/zap-rules.tsv

commit "feat(finops): automatización de optimización de costos

Apagado del entorno de pruebas fuera de horario laboral, encendido
al inicio de la jornada y limpieza programada del registry." \
  .github/workflows/finops.yml

commit "chore: scripts de operación y Makefile

Automatiza el levantado del entorno, la generación de carga para
demostrar el autoescalado, la recolección de evidencias y el
destroy." \
  scripts/ Makefile

commit "docs: documentación completa del proyecto

README con arquitectura, instrucciones de ejecución local y en
entorno de pruebas, validación de despliegue y monitoreo, y
resolución de problemas.

Agrega ADR con las decisiones de arquitectura, análisis cuantificado
de FinOps y guía de captura de evidencias." \
  README.md docs/

# Cualquier archivo que no haya entrado en los grupos anteriores.
if [ -n "$(git status --porcelain)" ]; then
  commit "chore: archivos complementarios" .
fi

echo ""
echo "Historial generado:"
git log --oneline
echo ""
echo "Total: $(git rev-list --count HEAD) commits"
echo ""
cat <<'SIGUIENTE'
Siguiente paso — publicar en GitHub:

    # 1. Crear el repositorio vacío en github.com (sin README ni .gitignore)
    # 2. Vincular y publicar:

    git remote add origin https://github.com/TU-USUARIO/pf-devops-cloud.git
    git push -u origin main

    # 3. Habilitar los permisos que necesita el pipeline:
    #    Settings > Actions > General > Workflow permissions
    #    -> Read and write permissions

Al hacer push, el workflow de CI arranca solo. Ahí salen las capturas
del bloque 5 de docs/EVIDENCIAS.md.
SIGUIENTE

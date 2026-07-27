# Pipeline CI/CD Integral — Task API

Proyecto final del curso **DevOps & Cloud**. Implementa un pipeline completo que
lleva una aplicación web desde el código fuente hasta un despliegue en
Kubernetes con auto-escalado, monitoreo, análisis de seguridad automatizado y
optimización de costos.

---

## Tabla de contenidos

- [Descripción del proyecto](#descripción-del-proyecto)
- [Arquitectura](#arquitectura)
- [Decisiones de diseño](#decisiones-de-diseño)
- [Estructura del repositorio](#estructura-del-repositorio)
- [Requisitos previos](#requisitos-previos)
- [Ejecución local](#ejecución-local)
- [Despliegue en el entorno de pruebas](#despliegue-en-el-entorno-de-pruebas)
- [Cómo validar el despliegue](#cómo-validar-el-despliegue)
- [Cómo validar el monitoreo](#cómo-validar-el-monitoreo)
- [Pipeline CI/CD](#pipeline-cicd)
- [Seguridad (DevSecOps)](#seguridad-devsecops)
- [FinOps](#finops)
- [Infraestructura en AWS](#infraestructura-en-aws)
- [Evidencias](#evidencias)
- [Solución de problemas](#solución-de-problemas)

---

## Descripción del proyecto

**Task API** es una API REST de gestión de tareas construida con FastAPI. La
aplicación es deliberadamente simple: el objeto de este proyecto no es la
complejidad del dominio, sino la cadena de automatización que la rodea.

Dicho esto, la aplicación no es un "hello world". Expone métricas Prometheus
propias desde el código (contadores de requests, histograma de latencias y un
gauge de negocio con las tareas por estado), emite logs estructurados en JSON y
separa las probes de *liveness* y *readiness*. Sin esa instrumentación, el
apartado de observabilidad sería decorativo.

### Qué cubre este repositorio

| Requisito de la consigna | Dónde está resuelto |
|---|---|
| Repositorio configurado | Este repo, con ramas `main`/`develop` y commits descriptivos |
| Dockerfile multi-stage optimizado | [`Dockerfile`](Dockerfile) |
| Terraform con variables y módulos | [`terraform/`](terraform/) — 3 módulos, 2 entornos |
| Pipeline CI/CD | [`.github/workflows/`](.github/workflows/) — 3 workflows, 12 jobs |
| Build y test automatizados | Job `quality` en `ci.yml` |
| Build y push de imágenes al registry | Job `build-and-push` en `ci.yml` |
| Provisionamiento con Terraform | Job `terraform-plan` en `cd.yml` |
| Despliegue en Kubernetes | Job `deploy` en `cd.yml` |
| Análisis SAST | Jobs `sast` y `codeql` en `ci.yml` |
| Análisis DAST | Job `dast` en `cd.yml` |
| Manifiestos: Pods, Service, Ingress | [`k8s/base/`](k8s/base/) |
| Auto-escalado con HPA | [`k8s/base/hpa.yaml`](k8s/base/hpa.yaml) |
| Prometheus y Grafana | [`monitoring/`](monitoring/) + `terraform/environments/local` |
| Configuraciones FinOps | [`.github/workflows/finops.yml`](.github/workflows/finops.yml) y a lo largo del repo |
| README con instrucciones y evidencias | Este archivo + [`docs/EVIDENCIAS.md`](docs/EVIDENCIAS.md) |

---

## Arquitectura

```
                        ┌──────────────────────────────┐
   git push ──────────► │      GitHub Actions — CI     │
                        ├──────────────────────────────┤
                        │  quality  │  sast  │  codeql │  ← en paralelo
                        │         iac-security         │
                        └──────────────┬───────────────┘
                                       │ todos en verde
                                       ▼
                        ┌──────────────────────────────┐
                        │   build-and-push  ──► GHCR   │
                        │   scan-image (Trivy)         │
                        └──────────────┬───────────────┘
                                       │
                        ┌──────────────▼───────────────┐
                        │      GitHub Actions — CD     │
                        ├──────────────────────────────┤
                        │ terraform-plan (AWS)         │
                        │ deploy  → cluster kind       │
                        │ dast    → OWASP ZAP          │
                        └──────────────┬───────────────┘
                                       ▼
        ┌──────────────────────────────────────────────────────┐
        │                  Cluster Kubernetes                  │
        │                                                      │
        │   Internet ──► Ingress (nginx) ──► Service           │
        │                                       │              │
        │                                       ▼              │
        │                            ┌──────────────────┐      │
        │                            │  Deployment      │      │
        │                            │  Pods task-api   │◄──┐  │
        │                            │  (2 a 8)         │   │  │
        │                            └────────┬─────────┘   │  │
        │                                     │ /metrics    │  │
        │                                     ▼             │  │
        │                            ┌──────────────┐       │  │
        │                            │  Prometheus  │       │  │
        │                            └──────┬───────┘       │  │
        │                                   │               │  │
        │                    ┌──────────────┴──┐     ┌──────┴─┐│
        │                    │    Grafana      │     │  HPA   ││
        │                    └─────────────────┘     └────────┘│
        │                                      metrics-server  │
        └──────────────────────────────────────────────────────┘
```

### Componentes

| Capa | Tecnología | Rol |
|---|---|---|
| Aplicación | Python 3.12 + FastAPI | API REST instrumentada |
| Contenedor | Docker multi-stage | Imagen mínima, sin toolchain, usuario no-root |
| Registry | GitHub Container Registry (GHCR) | Almacenamiento de imágenes |
| Orquestación | Kubernetes 1.31 | Deployment, Service, Ingress, HPA |
| IaC | Terraform 1.9 | Cluster local (kind) e infraestructura AWS |
| CI/CD | GitHub Actions | 3 workflows, 12 jobs |
| SAST | Bandit, Semgrep, CodeQL | Análisis estático |
| DAST | OWASP ZAP | Análisis dinámico contra la app desplegada |
| Contenedores | Trivy, Hadolint | Vulnerabilidades de imagen y buenas prácticas |
| IaC security | Checkov | Malas configuraciones en Terraform |
| Métricas | Prometheus | Recolección y alertas |
| Visualización | Grafana | Dashboards |

---

## Decisiones de diseño

Las decisiones no obvias están documentadas en
[`docs/DECISIONES.md`](docs/DECISIONES.md). Las tres más importantes:

**1. El entorno que se ejecuta es un cluster local, no AWS.**
El código Terraform para AWS (VPC, subnets, EKS, ECR) está escrito, es
funcional y se valida en cada corrida del pipeline, pero no se aplica de forma
automática. Un control plane de EKS cuesta unos US$73 por mes y no entra en la
capa gratuita. Para un proyecto formativo, aplicar esa infra significa asumir un
costo real y el riesgo de olvidarla encendida. El cluster `kind`, provisionado
igualmente con Terraform, ofrece un Kubernetes idéntico a nivel de API por
US$0. Las evidencias que se obtienen son igual de reales.

**2. El pipeline levanta su propio cluster efímero.**
El job de despliegue crea un cluster kind dentro del runner, despliega la
aplicación, la verifica y lo descarta al terminar. Esto permite tener un
despliegue real y un DAST real contra una aplicación realmente corriendo, sin
mantener infraestructura encendida entre corridas.

**3. La seguridad está distribuida en varias capas, no en un solo escáner.**
Análisis del código (Bandit, Semgrep, CodeQL), de las dependencias
(Dependabot), de la imagen (Trivy), del Dockerfile (Hadolint), de la
infraestructura (Checkov) y de la aplicación en ejecución (ZAP). Cada uno cubre
lo que los otros no ven.

---

## Estructura del repositorio

```
.
├── app/                          Código de la aplicación
│   ├── main.py                   Punto de entrada FastAPI
│   ├── config.py                 Configuración vía variables de entorno
│   ├── metrics.py                Instrumentación Prometheus
│   ├── logging_config.py         Logs estructurados en JSON
│   ├── models.py                 Esquemas Pydantic
│   ├── store.py                  Almacenamiento en memoria
│   └── routers/                  Endpoints (health, tasks)
├── tests/                        Tests unitarios (18 casos, 99 % cobertura)
├── Dockerfile                    Build multi-stage
├── docker-compose.yml            Entorno local: app + Prometheus + Grafana
├── terraform/
│   ├── modules/
│   │   ├── network/              VPC, subnets, NAT, route tables
│   │   ├── cluster/              EKS, node group SPOT, IAM, KMS
│   │   └── app-registry/         ECR con lifecycle policies
│   └── environments/
│       ├── local/                Cluster kind + Helm (el que se ejecuta)
│       └── aws/                  Composición de los tres módulos
├── k8s/base/                     Manifiestos Kubernetes
├── monitoring/                   ServiceMonitor, alertas, dashboard Grafana
├── .github/
│   ├── workflows/                ci.yml, cd.yml, finops.yml
│   ├── kind-ci.yaml              Cluster efímero del pipeline
│   ├── zap-rules.tsv             Reglas de DAST
│   └── dependabot.yml            Actualización de dependencias
├── scripts/                      setup-local, load-test, evidencias, teardown
├── docs/                         Decisiones, evidencias, análisis de costos
└── Makefile                      Atajos de desarrollo y operación
```

---

## Publicar el repositorio

El proyecto incluye un script que genera un historial de 16 commits temáticos
con mensajes descriptivos en formato Conventional Commits, agrupando los
archivos por unidad de trabajo. Se ejecuta con tu propia identidad de git.

```bash
chmod +x scripts/init-git.sh
./scripts/init-git.sh

git remote add origin https://github.com/TU-USUARIO/pf-devops-cloud.git
git push -u origin main
```

Después del push, habilitá los permisos que el pipeline necesita para publicar
imágenes: *Settings → Actions → General → Workflow permissions → Read and write
permissions*. El workflow de CI arranca automáticamente con el primer push.

---

## Requisitos previos

| Herramienta | Versión mínima | Para qué |
|---|---|---|
| Docker | 24.0 | Contenedores y nodos de kind |
| Terraform | 1.6 | Provisionamiento |
| kubectl | 1.28 | Interacción con el cluster |
| kind | 0.24 | Cluster Kubernetes local |
| Helm | 3.14 | Instalación de Ingress y monitoreo |
| kustomize | 5.0 | Sustitución de la imagen en los manifiestos |
| Python | 3.12 | Desarrollo y tests |
| make | — | Atajos (opcional) |

<details>
<summary><b>Instalación en Ubuntu / Debian</b></summary>

```bash
# Docker
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker "$USER" && newgrp docker

# kubectl
curl -LO "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -m 0755 kubectl /usr/local/bin/kubectl && rm kubectl

# kind
curl -Lo kind https://kind.sigs.k8s.io/dl/v0.24.0/kind-linux-amd64
sudo install -m 0755 kind /usr/local/bin/kind && rm kind

# Helm
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# kustomize
curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash
sudo mv kustomize /usr/local/bin/

# Terraform
wget -O - https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
  | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install terraform
```
</details>

Recursos recomendados para la máquina: 4 CPU y 8 GB de RAM. El stack de
monitoreo es lo que más consume.

---

## Ejecución local

### Opción A — Solo la aplicación

```bash
git clone <URL-DEL-REPOSITORIO> && cd pf-devops-cloud
make init                    # instala dependencias y habilita los scripts
make run                     # http://localhost:8000/docs
```

Verificación rápida:

```bash
curl http://localhost:8000/health/live
curl -X POST http://localhost:8000/api/v1/tasks \
  -H 'Content-Type: application/json' \
  -d '{"title":"Mi primera tarea"}'
curl http://localhost:8000/metrics | grep http_requests_total
```

### Opción B — Con Docker Compose (app + Prometheus + Grafana)

Es la vía más rápida para ver el ciclo completo de métricas sin Kubernetes.

```bash
cp .env.example .env         # completar con valores propios
make compose-up
```

| Servicio | URL | Credenciales |
|---|---|---|
| Aplicación | http://localhost:8000/docs | — |
| Prometheus | http://localhost:9090 | — |
| Grafana | http://localhost:3000 | `admin` / `admin` |

En Grafana, el dashboard **Task API — Visión general** ya viene provisionado
dentro de la carpeta *Task API*. Generá algo de tráfico contra la API y los
paneles empiezan a poblarse.

```bash
make compose-down            # al terminar
```

### Ejecutar los controles de calidad

```bash
make check                   # lint + tests + SAST, lo mismo que corre en CI
```

---

## Despliegue en el entorno de pruebas

Un solo comando levanta el entorno completo: cluster Kubernetes provisionado
con Terraform, Ingress Controller, metrics-server, Prometheus, Grafana y la
aplicación desplegada.

```bash
make up
```

El proceso toma entre 5 y 8 minutos la primera vez (descarga de imágenes) y
ejecuta, en orden:

1. Verifica que estén todas las herramientas requeridas.
2. `terraform apply` sobre `terraform/environments/local` → crea el cluster kind
   de 3 nodos e instala vía Helm el Ingress Controller, metrics-server y el
   stack `kube-prometheus-stack`.
3. Construye la imagen Docker y la carga en los nodos del cluster.
4. Crea el namespace y genera el Secret en el momento (su valor nunca se
   versiona).
5. Aplica los manifiestos con kustomize y espera el rollout.
6. Registra el dashboard de Grafana y aplica el ServiceMonitor y las alertas.

Agregá una única vez la entrada al archivo de hosts para poder resolver el
Ingress:

```bash
echo "127.0.0.1 task-api.local" | sudo tee -a /etc/hosts
```

### Accesos

| Servicio | Cómo llegar |
|---|---|
| Aplicación | http://task-api.local:8080 |
| Swagger UI | http://task-api.local:8080/docs |
| Métricas | http://task-api.local:8080/metrics |
| Grafana | `make grafana` → http://localhost:3000 (`admin`/`admin`) |
| Prometheus | `make prometheus` → http://localhost:9090 |

### Destruir el entorno

```bash
make down
```

---

## Cómo validar el despliegue

### 1. Los recursos existen y están sanos

```bash
make status
```

Se espera ver el Deployment con todas las réplicas listas, un Service de tipo
`ClusterIP`, el Ingress con dirección asignada y el HPA reportando métricas (no
`<unknown>`).

### 2. La aplicación responde a través del Ingress

```bash
curl http://task-api.local:8080/health/live
curl http://task-api.local:8080/api/v1/tasks

curl -X POST http://task-api.local:8080/api/v1/tasks \
  -H 'Content-Type: application/json' \
  -d '{"title":"Validación del despliegue"}'
```

### 3. El contenedor no corre como root

```bash
kubectl exec -n task-api deploy/task-api -- id
# uid=10001(appuser) gid=10001(appuser)
```

### 4. El auto-escalado funciona

Esta es la verificación más vistosa y la que conviene capturar para el informe.
En una terminal:

```bash
watch -n 2 'kubectl get hpa,pods -n task-api'
```

En otra:

```bash
make load          # 5 minutos de carga con 40 workers concurrentes
```

Se debe observar el porcentaje de CPU subiendo por encima del objetivo del 60 %
y la cantidad de réplicas creciendo de 2 hacia el máximo de 8. Al cortar la
carga, el HPA tarda unos 5 minutos en reducir réplicas: es el
`stabilizationWindowSeconds: 300` que evita el *flapping*.

### 5. El despliegue es sin downtime

```bash
# En una terminal, tráfico continuo:
while true; do curl -s -o /dev/null -w "%{http_code} " http://task-api.local:8080/health/ready; sleep 0.2; done

# En otra, forzar un redespliegue:
kubectl rollout restart deployment/task-api -n task-api
```

No debería aparecer ningún código distinto de `200`: es el efecto de
`maxUnavailable: 0` combinado con la `readinessProbe`.

---

## Cómo validar el monitoreo

### Prometheus está scrapeando la aplicación

```bash
make prometheus     # y abrir http://localhost:9090
```

En **Status → Targets** debe figurar el target `task-api` en estado `UP`.

Consultas útiles para probar en la pestaña *Graph*:

```promql
# Requests por segundo
sum(rate(http_requests_total[1m]))

# Latencia p95
histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket[5m])) by (le))

# Tareas almacenadas por estado (métrica de negocio)
sum by (status) (tasks_total)

# Tasa de error
sum(rate(http_requests_total{status_code=~"5.."}[5m])) / sum(rate(http_requests_total[5m]))
```

### Grafana muestra el dashboard

```bash
make grafana        # y abrir http://localhost:3000
```

Carpeta *Task API* → dashboard **Task API — Visión general**, con 11 paneles
organizados en tres secciones: estado del servicio, tráfico y latencia, y
negocio y escalado.

Para que los paneles tengan datos, generá tráfico antes:

```bash
make load
```

### Las alertas están cargadas

```bash
kubectl get prometheusrules -n monitoring
```

En Prometheus, la pestaña **Alerts** debe listar las cuatro reglas definidas en
`monitoring/prometheus-rules.yaml`: alta tasa de errores, latencia alta,
ausencia de réplicas y HPA en el límite.

---

## Pipeline CI/CD

### Workflow `ci.yml` — Integración continua

Se dispara con cada push a `main`/`develop` y en cada pull request.

| Job | Qué hace | Falla si |
|---|---|---|
| `quality` | Ruff (lint + formato), pytest con cobertura | Cobertura menor al 80 % o algún test falla |
| `sast` | Bandit + Semgrep, resultados en formato SARIF | — (informativo, se publica en Security) |
| `codeql` | Análisis semántico de GitHub | Vulnerabilidades de severidad alta |
| `iac-security` | `terraform fmt`/`validate`, Checkov, Hadolint, kubeconform | Formato incorrecto, manifiesto inválido o warning de Hadolint |
| `build-and-push` | Build multi-stage, push a GHCR con SBOM y procedencia | Error de build |
| `scan-image` | Trivy sobre la imagen publicada | Vulnerabilidad `CRITICAL` con fix disponible |

Los primeros cuatro jobs corren **en paralelo**; el build solo arranca si todos
pasaron.

### Workflow `cd.yml` — Despliegue

Se dispara automáticamente cuando CI termina bien en `main`.

| Job | Qué hace |
|---|---|
| `terraform-plan` | Valida el entorno AWS y genera el plan si hay credenciales OIDC |
| `deploy` | Cluster kind efímero → despliega → verifica rollout → smoke tests → recolecta evidencias |
| `dast` | OWASP ZAP baseline + API scan contra la aplicación en ejecución |

Las evidencias del despliegue y los reportes de ZAP quedan como artefactos
descargables de cada corrida.

### Workflow `finops.yml` — Optimización de costos

| Disparador | Acción |
|---|---|
| 20:00 ART, lunes a viernes | Escala el node group a 0 nodos |
| 08:00 ART, lunes a viernes | Restaura el node group a 2 nodos |
| Domingos 00:00 ART | Limpia imágenes antiguas del registry |
| Manual | Reporte de costos desde AWS Cost Explorer |

### Secretos y variables a configurar

El pipeline funciona sin ninguna configuración adicional: usa el
`GITHUB_TOKEN` efímero para publicar en GHCR y omite con elegancia los pasos
que requieren AWS. Para habilitar las funciones que sí necesitan la nube:

| Nombre | Tipo | Descripción |
|---|---|---|
| `APP_API_KEY` | Secret | Clave de la aplicación inyectada en el despliegue |
| `AWS_ROLE_ARN` | Variable | Rol IAM asumible vía OIDC (sin claves estáticas) |
| `AWS_REGION` | Variable | Región, por defecto `us-east-1` |
| `EKS_CLUSTER_NAME` | Variable | Cluster objetivo del apagado programado |

Se configuran en *Settings → Secrets and variables → Actions*.

---

## Seguridad (DevSecOps)

### Análisis automatizado

| Capa | Herramienta | Momento | Tipo |
|---|---|---|---|
| Código fuente | Bandit | Cada push | SAST |
| Código fuente | Semgrep (OWASP Top 10) | Cada push | SAST |
| Código fuente | CodeQL | Cada push | SAST |
| Dependencias | Dependabot | Semanal | SCA |
| Dockerfile | Hadolint | Cada push | Linting de seguridad |
| Imagen | Trivy | Tras el build | Escaneo de vulnerabilidades |
| Infraestructura | Checkov | Cada push | IaC scanning |
| Aplicación corriendo | OWASP ZAP | Tras el despliegue | DAST |

Todos los hallazgos se publican en formato SARIF y quedan visibles en la
pestaña **Security → Code scanning** del repositorio.

### Endurecimiento aplicado

**En la imagen:** build multi-stage que deja el toolchain de compilación fuera
de la imagen final, usuario no-root con UID fijo (10001), imagen base slim
oficial, y metadatos OCI que trazan qué commit generó qué artefacto.

**En Kubernetes:** `runAsNonRoot`, `readOnlyRootFilesystem`,
`allowPrivilegeEscalation: false`, todas las capabilities de Linux descartadas,
perfil seccomp por defecto, Pod Security Standards en modo `restricted` a nivel
namespace, y una NetworkPolicy que restringe el tráfico entrante al Ingress
Controller y a Prometheus, y el saliente únicamente a DNS.

**En la gestión de secretos:** ningún valor sensible está versionado. El Secret
de Kubernetes se genera en tiempo de despliegue desde GitHub Secrets. El
`.gitignore` bloquea `.env`, `*.tfvars`, `*.pem` y archivos de estado de
Terraform. La autenticación con AWS es vía OIDC, sin claves de acceso
almacenadas.

> **Nota honesta sobre los Secret de Kubernetes:** están codificados en base64,
> no cifrados. Para un entorno productivo real corresponde External Secrets
> Operator con AWS Secrets Manager, o Sealed Secrets. Está fuera del alcance de
> este proyecto pero es la evolución natural.

---

## FinOps

La optimización de costos no es un workflow aislado: aparece en varias capas
del proyecto.

| Medida | Dónde | Impacto |
|---|---|---|
| Instancias SPOT para los nodos | `terraform/modules/cluster` | 70–90 % menos que on-demand |
| Un solo NAT Gateway compartido | `terraform/modules/network` | Ahorra ~US$32/mes por AZ evitada |
| Apagado nocturno y de fin de semana | `.github/workflows/finops.yml` | ~65 % del cómputo (se pagan ~60 h de 168 semanales) |
| `requests` y `limits` ajustados | `k8s/base/deployment.yaml` | Evita reservar capacidad ociosa |
| HPA con `minReplicas: 2` | `k8s/base/hpa.yaml` | Mínimo para HA, sin sobredimensionar |
| HPA con `maxReplicas: 8` | `k8s/base/hpa.yaml` | Techo de gasto ante un pico o un ataque |
| Lifecycle policy en ECR | `terraform/modules/app-registry` | Retiene 10 imágenes; el resto expira |
| Limpieza programada de GHCR | `.github/workflows/finops.yml` | Evita crecimiento indefinido |
| Retención de logs a 7 días | `terraform/modules/cluster` | CloudWatch no crece sin límite |
| `Service` de tipo ClusterIP + un Ingress | `k8s/base/` | Un load balancer en vez de uno por servicio (~US$18/mes cada uno) |
| `concurrency` con cancelación | `ci.yml` | Menos minutos de runner consumidos |
| Caché de capas en el build | `ci.yml` | Builds más cortos |
| Tag `CostCenter` en todos los recursos | `terraform/environments/aws` | Permite atribuir el gasto en Cost Explorer |

El análisis cuantificado, con la estimación mensual comparando la configuración
sin optimizar y la optimizada, está en
[`docs/COSTOS.md`](docs/COSTOS.md).

---

## Infraestructura en AWS

El código Terraform del directorio `terraform/environments/aws` está completo y
se valida en cada corrida del pipeline, pero **no se aplica automáticamente**
por los motivos explicados en [Decisiones de diseño](#decisiones-de-diseño).

Si querés desplegarlo de verdad:

```bash
cd terraform/environments/aws

# 1. Crear previamente el bucket S3 y la tabla DynamoDB del estado remoto
cp backend.hcl.example backend.hcl && $EDITOR backend.hcl
cp terraform.tfvars.example terraform.tfvars && $EDITOR terraform.tfvars

# 2. Provisionar
terraform init -backend-config=backend.hcl
terraform plan
terraform apply

# 3. Conectar kubectl
aws eks update-kubeconfig --name $(terraform output -raw cluster_name)
```

> **Advertencia de costo.** Esta infraestructura factura mientras esté
> encendida: control plane de EKS (~US$73/mes), nodos EC2 SPOT (~US$10/mes con
> t3.small) y NAT Gateway (~US$32/mes). Estimado total: **US$115–130 por mes**.
> Al terminar, `terraform destroy`.

### Qué crea

- VPC `10.0.0.0/16` con subnets públicas y privadas en dos zonas de
  disponibilidad, Internet Gateway y NAT Gateway compartido.
- Cluster EKS 1.31 con endpoint privado y público, secrets de etcd cifrados con
  KMS y logs del control plane en CloudWatch con retención de 7 días.
- Node group gestionado con instancias SPOT (`t3.small` / `t3a.small`), entre 2
  y 4 nodos.
- Repositorio ECR con escaneo en el push, tags inmutables y política de ciclo de
  vida.
- Roles IAM con los permisos mínimos necesarios.

---

## Evidencias

La consigna pide evidencias que demuestren el funcionamiento. El repositorio
incluye dos mecanismos:

**Automático:** cada corrida del workflow `cd.yml` publica el artefacto
`evidencias-despliegue` con el estado de todos los recursos, la descripción del
Deployment, HPA e Ingress, los logs de la aplicación, los eventos del namespace
y el consumo de recursos.

**Local:**

```bash
make evidencias
```

Genera un directorio con marca de tiempo bajo `evidencias/` con 15 archivos que
capturan el estado completo del entorno.

La guía de qué capturas de pantalla tomar, en qué momento exacto y qué debe
verse en cada una está en [`docs/EVIDENCIAS.md`](docs/EVIDENCIAS.md).

---

## Solución de problemas

<details>
<summary><b>El HPA muestra <code>&lt;unknown&gt;</code> en la columna de targets</b></summary>

metrics-server todavía no reportó datos. Esperá entre 60 y 90 segundos tras el
despliegue. Si persiste:

```bash
kubectl logs -n kube-system deploy/metrics-server
kubectl top nodes    # debe devolver valores, no un error
```

En kind el problema típico es la validación de certificados TLS del kubelet; el
flag `--kubelet-insecure-tls` ya viene aplicado en el Terraform local.
</details>

<details>
<summary><b><code>task-api.local</code> no resuelve</b></summary>

Falta la entrada en el archivo de hosts:

```bash
echo "127.0.0.1 task-api.local" | sudo tee -a /etc/hosts
```

Alternativa sin tocar `/etc/hosts`:

```bash
curl -H "Host: task-api.local" http://localhost:8080/health/live
```
</details>

<details>
<summary><b>Los Pods quedan en <code>ImagePullBackOff</code></b></summary>

La imagen no llegó a los nodos del cluster. kind no comparte el daemon de
Docker del host:

```bash
docker build -t task-api:local .
kind load docker-image task-api:local --name task-api-local
kubectl rollout restart deployment/task-api -n task-api
```
</details>

<details>
<summary><b>El Ingress Controller no arranca</b></summary>

Revisá que los puertos 8080 y 8443 del host estén libres:

```bash
sudo lsof -i :8080
```

Si están ocupados, cambiá `ingress_http_port` en
`terraform/environments/local/variables.tf` y volvé a aplicar.
</details>

<details>
<summary><b><code>terraform apply</code> falla al crear el cluster kind</b></summary>

Suele ser un cluster previo con el mismo nombre:

```bash
kind delete cluster --name task-api-local
cd terraform/environments/local && rm -f terraform.tfstate*
terraform apply
```
</details>

<details>
<summary><b>Los scripts no tienen permisos de ejecución</b></summary>

```bash
chmod +x scripts/*.sh
```

Los objetivos del Makefile ya lo hacen automáticamente.
</details>

---

## Licencia

MIT — proyecto con fines educativos.

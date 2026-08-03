# Guía de operación del entorno local

Instructivo práctico para entender, levantar, verificar y apagar el entorno
local de este proyecto. Pensado para operar el día a día, no para la teoría
(esa está en [`DECISIONES.md`](DECISIONES.md) y el [`README`](../README.md)).

> **Nota sobre este entorno:** corre en **Windows con Docker Desktop**, usando
> Git Bash y herramientas instaladas con winget (`kubectl`, `kind`, `helm`,
> `kustomize`). Todo el Kubernetes vive dentro de Docker (kind = *Kubernetes IN
> Docker*), así que si Docker Desktop está apagado, no hay cluster.

---

## 1. Qué es cada cosa (el diseño en 2 minutos)

Cuando levantás el entorno, se crean **dos planos** de cosas: la infraestructura
(el cluster y la plataforma) y la aplicación.

```
   Tu navegador / curl
        │
        ▼  http://task-api.local:8080
   ┌─────────────────┐
   │  Ingress-nginx  │   Puerta de entrada. Rutea por hostname al Service.
   └────────┬────────┘
            ▼
   ┌─────────────────┐
   │  Service        │   Nombre estable + balanceo entre las réplicas.
   │  (ClusterIP)    │
   └────────┬────────┘
            ▼
   ┌─────────────────┐        ┌──────────────┐
   │  Deployment     │◄───────│     HPA      │  Sube/baja réplicas según CPU.
   │  Pods task-api  │        └──────────────┘
   │  (2 a 8)        │
   └────────┬────────┘
            │ /metrics (cada pod expone sus métricas en :8000)
            ▼
   ┌─────────────────┐        ┌──────────────┐
   │   Prometheus    │───────►│   Grafana    │  Dashboards.
   │  (scrapea)      │        └──────────────┘
   └─────────────────┘
```

| Componente | Namespace | Para qué sirve |
|---|---|---|
| **kind cluster** | — | El Kubernetes en sí, 3 nodos corriendo como contenedores Docker |
| **Ingress-nginx** | `ingress-nginx` | Recibe el tráfico HTTP del host (puerto 8080) y lo mete al cluster |
| **metrics-server** | `kube-system` | Mide CPU/memoria de los pods; **sin esto el HPA no funciona** |
| **task-api** | `task-api` | La aplicación (Deployment + Service + Ingress + HPA + NetworkPolicy) |
| **HPA** | `task-api` | Autoescalado horizontal: 2 réplicas mínimo, 8 máximo, objetivo 60% CPU |
| **Prometheus** | `monitoring` | Recolecta las métricas de la app y evalúa las alertas |
| **Grafana** | `monitoring` | Muestra los dashboards (usuario `admin` / `admin`) |

**Dato clave sobre los datos:** la app guarda las tareas **en memoria, por
réplica**. No hay base de datos. Como hay 2 réplicas y el Service balancea, dos
`GET` seguidos pueden pegar en réplicas distintas y devolver estados distintos.
Es **a propósito** (ADR-005: app *stateless* para que el HPA escale sin
coordinar estado). Para ver el CRUD coherente, usá Docker Compose (una sola
instancia): `make compose-up`.

---

## 2. Prender y apagar

### Prender todo el entorno (desde cero)

```bash
./scripts/setup-local.sh      # o "make up" si tenés make
```

Tarda 5-8 minutos la primera vez. Levanta el cluster, la plataforma y la app.

### Apagar

Hay dos niveles, según qué quieras:

| Qué querés | Comando | Qué pasa |
|---|---|---|
| **Liberar RAM un rato** sin perder nada | Apagar Docker Desktop, o `docker stop` de los contenedores `task-api-local-*` | El cluster queda "pausado"; al reabrir Docker vuelve solo |
| **Destruir el entorno** | `./scripts/teardown.sh` (o `make down`) | Borra el cluster kind entero. Para volver, `setup-local.sh` de nuevo |

> Recomendación: si vas a seguir en un rato, apagá Docker Desktop nomás. Si
> terminaste, usá `teardown.sh` para no dejar contenedores ocupando recursos.

### Volver a levantar tras reiniciar la PC o Docker

**Importante:** kind sobre Docker Desktop **no sobrevive bien a un reinicio de la
máquina**. Los contenedores vuelven a arrancar, pero Docker Desktop pierde el
mapeo del puerto dinámico de la API de Kubernetes, y kubectl deja de conectar:

```
Unable to connect to the server: dial tcp 127.0.0.1:XXXXX: connection refused
```

Se reconoce mirando `docker ps`: el puerto `6443/tcp` del control-plane aparece
**sin** su mapeo al host (a diferencia de `0.0.0.0:8080->80/tcp`, que sí lo
tiene). El `docker restart` no lo arregla (suele empeorarlo).

La solución confiable es **recrear el cluster** (rápido, porque las imágenes ya
están cacheadas):

```bash
kind delete cluster --name task-api-local
cd terraform/environments/local && rm -f terraform.tfstate*
cd ../../.. && ./scripts/setup-local.sh
```

> Es coherente con la filosofía del proyecto: el entorno local es **efímero y
> descartable**. No está pensado para vivir entre reinicios, sino para levantarse
> cuando se necesita (por ejemplo, para capturar evidencias) y destruirse después.

---

## 3. Cómo verificar que cada cosa funciona

### Salud general (una sola mirada)

```bash
kubectl get deploy,pod,svc,ingress,hpa -n task-api
```

Qué querés ver:
- Deployment `2/2` (o más si el HPA escaló).
- Pods en `Running` y `1/1`.
- HPA con números reales en TARGETS (ej. `cpu: 4%/60%`), **no `<unknown>`**.

### La app responde

```bash
# Por línea de comandos (siempre funciona, no depende del hosts):
curl -H "Host: task-api.local" http://localhost:8080/health/live
curl -H "Host: task-api.local" http://localhost:8080/api/v1/tasks
```

### El contenedor no corre como root (evidencia de seguridad)

```bash
kubectl exec -n task-api deploy/task-api -- id
# esperado: uid=10001(appuser) gid=10001(appuser)
```

### Prometheus está scrapeando la app

```bash
kubectl port-forward -n monitoring svc/monitoring-prometheus 9090:9090
# abrir http://localhost:9090  ->  Status > Targets  ->  task-api debe estar UP
```

### Grafana muestra el dashboard

```bash
kubectl port-forward -n monitoring svc/monitoring-grafana 3000:80
# abrir http://localhost:3000  (admin / admin)
# carpeta "Task API" -> dashboard "Task API — Visión general"
```

> Los `port-forward` son **bloqueantes**: ocupan la terminal mientras están
> activos. Abrí una terminal por cada uno, o cortá con `Ctrl+C` cuando termines.

---

## 4. Accesos

Para el acceso por navegador a `task-api.local`, agregá una vez (PowerShell como
Administrador):

```powershell
Add-Content -Path "$env:windir\System32\drivers\etc\hosts" -Value "`n127.0.0.1 task-api.local"
```

| Servicio | URL / comando |
|---|---|
| App (Swagger) | http://task-api.local:8080/docs |
| App (métricas) | http://task-api.local:8080/metrics |
| Grafana | `kubectl port-forward -n monitoring svc/monitoring-grafana 3000:80` → http://localhost:3000 |
| Prometheus | `kubectl port-forward -n monitoring svc/monitoring-prometheus 9090:9090` → http://localhost:9090 |

---

## 5. Ver el autoescalado (lo más vistoso para el informe)

En una terminal, mirá el HPA en vivo:

```bash
kubectl get hpa,pods -n task-api -w
```

En otra, generá carga:

```bash
./scripts/load-test.sh
```

Vas a ver el % de CPU pasar el objetivo (60%) y las réplicas creciendo de 2
hacia 8. Al cortar la carga, el HPA **tarda ~5 minutos** en bajar réplicas: es el
`stabilizationWindowSeconds: 300`, puesto a propósito para evitar el *flapping*.

---

## 6. Problemas comunes

| Síntoma | Causa / solución |
|---|---|
| `services "..." not found` en port-forward | El Service de Prometheus es `monitoring-prometheus` (no `...-kube-prometheus-prometheus`) |
| HPA en `<unknown>` | metrics-server tarda 60-90 s tras el arranque. Si persiste: `kubectl top nodes` |
| Pods en `ImagePullBackOff` | La imagen no llegó a los nodos: `docker build -t task-api:local . && kind load docker-image task-api:local --name task-api-local` |
| `task-api.local` no resuelve en el navegador | Falta la línea en el hosts de Windows (ver sección 4) |
| Cada GET devuelve algo distinto | No es un bug: 2 réplicas con memoria propia (ADR-005). Para CRUD coherente, `make compose-up` |
| `Unable to connect to the server` / `connection refused` tras reiniciar la PC | kind perdió el puerto de la API. **Recreá el cluster** (ver "Volver a levantar tras reiniciar la PC" en la sección 2) |

---

## 7. Comandos de referencia rápida

```bash
# Estado
kubectl get all -n task-api
kubectl get pods -A                      # todos los namespaces
kubectl logs -n task-api deploy/task-api -f   # logs de la app en vivo

# La app
curl -H "Host: task-api.local" http://localhost:8080/health/ready

# Monitoreo (cada uno bloquea su terminal)
kubectl port-forward -n monitoring svc/monitoring-grafana 3000:80
kubectl port-forward -n monitoring svc/monitoring-prometheus 9090:9090

# Ciclo de vida
./scripts/setup-local.sh    # prender
./scripts/load-test.sh      # generar carga (autoescalado)
./scripts/evidencias.sh     # recolectar evidencias para el informe
./scripts/teardown.sh       # destruir el entorno
```

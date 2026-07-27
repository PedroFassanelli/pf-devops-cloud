# Guía de captura de evidencias

La consigna pide evidencias que demuestren el funcionamiento del pipeline. Esta
guía indica **qué capturar, en qué momento y qué debe verse** en cada imagen.

Guardá las capturas en `evidencias/capturas/` con los nombres sugeridos: así
después se insertan en el informe sin tener que adivinar cuál es cuál.

---

## Antes de empezar

```bash
make up                        # levanta el entorno completo
echo "127.0.0.1 task-api.local" | sudo tee -a /etc/hosts
```

Esperá a que el rollout termine antes de capturar nada. Una captura con Pods en
`ContainerCreating` no demuestra que algo funcione.

---

## Bloque 1 — Aplicación y contenedor

### `01-tests-locales.png`
**Comando:** `make check`
**Debe verse:** los 18 tests en verde, la cobertura por encima del 80 % y los
controles de ruff y bandit sin hallazgos.

### `02-build-imagen.png`
**Comando:** `make build`
**Debe verse:** las dos etapas del build multi-stage y el tamaño final de la
imagen. Este es el dato que demuestra la optimización: anotalo, lo vas a citar
en el informe.

### `03-imagen-sin-root.png`
**Comando:** `docker run --rm --entrypoint id task-api:local`
**Debe verse:** `uid=10001(appuser)`. Es la evidencia de que el contenedor no
corre como root.

### `04-swagger.png`
**URL:** http://task-api.local:8080/docs
**Debe verse:** la documentación OpenAPI generada automáticamente, con los
endpoints de health y tasks.

---

## Bloque 2 — Kubernetes

### `05-recursos-desplegados.png`
**Comando:** `make status`
**Debe verse:** Deployment con réplicas listas, Service `ClusterIP`, Ingress con
dirección asignada y HPA reportando métricas reales (no `<unknown>`).

### `06-pods-distribuidos.png`
**Comando:** `kubectl get pods -n task-api -o wide`
**Debe verse:** los Pods repartidos en distintos nodos. Es la evidencia de que
funcionan los `topologySpreadConstraints`.

### `07-ingress.png`
**Comando:** `kubectl describe ingress task-api -n task-api`
**Debe verse:** la regla de host `task-api.local` apuntando al Service.

### `08-app-por-ingress.png`
**Comando:**
```bash
curl -i http://task-api.local:8080/api/v1/tasks
curl -X POST http://task-api.local:8080/api/v1/tasks \
  -H 'Content-Type: application/json' -d '{"title":"Evidencia"}'
```
**Debe verse:** respuestas `200` y `201`. Demuestra el camino completo
Ingress → Service → Pod.

### `09-logs-json.png`
**Comando:** `kubectl logs -n task-api -l app.kubernetes.io/name=task-api --tail=20`
**Debe verse:** los logs estructurados en JSON, con timestamp, nivel y mensaje.

---

## Bloque 3 — Auto-escalado (el más importante)

Necesita **tres capturas en momentos distintos**. Preparate antes: abrí una
terminal con el `watch` corriendo y otra para lanzar la carga.

```bash
# Terminal 1
watch -n 2 'kubectl get hpa,pods -n task-api'

# Terminal 2
make load
```

### `10-hpa-reposo.png`
**Momento:** antes de lanzar la carga.
**Debe verse:** el HPA con 2 réplicas y el uso de CPU bajo (algo como `3%/60%`).

### `11-hpa-escalando.png`
**Momento:** entre 1 y 3 minutos después de iniciada la carga.
**Debe verse:** el porcentaje de CPU por encima del objetivo del 60 % y la
cantidad de réplicas creciendo por encima de 2. Es **la** captura del punto de
auto-escalado.

### `12-hpa-eventos.png`
**Comando:** `kubectl describe hpa task-api -n task-api`
**Debe verse:** la sección `Events` con los mensajes `SuccessfulRescale`
indicando el motivo del escalado.

### `13-hpa-descenso.png`
**Momento:** unos 5-6 minutos después de terminar la carga.
**Debe verse:** las réplicas volviendo hacia 2. Documenta que la ventana de
estabilización de 300 segundos funciona como se diseñó.

---

## Bloque 4 — Monitoreo

```bash
make prometheus     # terminal aparte
make grafana        # otra terminal
```

Generá tráfico antes de capturar, o los paneles van a estar vacíos.

### `14-prometheus-targets.png`
**URL:** http://localhost:9090 → Status → Targets
**Debe verse:** el target `task-api` en estado `UP`, con los Pods listados.

### `15-prometheus-query.png`
**URL:** http://localhost:9090 → Graph
**Consulta:** `sum(rate(http_requests_total[1m]))`
**Debe verse:** el gráfico con datos reales.

### `16-prometheus-alertas.png`
**URL:** http://localhost:9090 → Alerts
**Debe verse:** las cuatro reglas cargadas.

### `17-grafana-dashboard.png`
**URL:** http://localhost:3000 → carpeta *Task API*
**Debe verse:** el dashboard completo con los paneles poblados. Capturá después
de haber corrido `make load`, así los gráficos tienen forma.

### `18-grafana-negocio.png`
**Debe verse:** el panel *Tareas almacenadas por estado*. Es la evidencia de que
la aplicación expone métricas propias, no solo métricas de infraestructura.

### `19-grafana-escalado.png`
**Debe verse:** el panel *Autoescalado: réplicas vs. límites* mostrando el pico
de la prueba de carga.

---

## Bloque 5 — Pipeline CI/CD

Estas capturas salen de GitHub, después de hacer push.

### `20-ci-completo.png`
**Dónde:** pestaña Actions → última corrida de CI
**Debe verse:** los seis jobs en verde y el grafo mostrando el paralelismo.

### `21-ci-tests.png`
**Dónde:** job `quality`, paso de tests
**Debe verse:** el reporte de cobertura.

### `22-ci-sast.png`
**Dónde:** job `sast` o `codeql`
**Debe verse:** el análisis ejecutándose sin errores.

### `23-security-tab.png`
**Dónde:** pestaña Security → Code scanning
**Debe verse:** los hallazgos publicados por Bandit, CodeQL, Checkov y Trivy.
Esta captura demuestra que el SAST no solo corre, sino que reporta.

### `24-imagen-ghcr.png`
**Dónde:** pestaña Packages del repositorio
**Debe verse:** la imagen publicada con sus tags.

### `25-cd-completo.png`
**Dónde:** Actions → última corrida de CD
**Debe verse:** los tres jobs en verde.

### `26-cd-despliegue.png`
**Dónde:** job `deploy`, paso *Verificar el estado del despliegue*
**Debe verse:** la salida de `kubectl get` con todos los recursos creados dentro
del pipeline.

### `27-cd-smoke-tests.png`
**Dónde:** job `deploy`, paso *Smoke tests contra el Ingress*
**Debe verse:** las respuestas de la API desde dentro del pipeline.

### `28-dast-zap.png`
**Dónde:** job `dast`
**Debe verse:** el resumen del escaneo de OWASP ZAP.

### `29-artefactos.png`
**Dónde:** resumen de la corrida de CD, sección Artifacts
**Debe verse:** `evidencias-despliegue` y `reportes-dast` disponibles.

---

## Bloque 6 — FinOps

### `30-finops-workflow.png`
**Dónde:** Actions → workflow FinOps → *Run workflow* → acción `apagar`
**Debe verse:** el resumen del job con el detalle de la acción ejecutada o
simulada.

### `31-recursos-configurados.png`
**Comando:**
```bash
kubectl get pods -n task-api -o custom-columns='POD:.metadata.name,CPU_REQ:.spec.containers[0].resources.requests.cpu,MEM_REQ:.spec.containers[0].resources.requests.memory,CPU_LIM:.spec.containers[0].resources.limits.cpu,MEM_LIM:.spec.containers[0].resources.limits.memory'
```
**Debe verse:** requests y limits definidos en todos los Pods.

---

## Bloque 7 — Terraform

### `32-terraform-apply.png`
**Comando:** durante `make up`, el tramo de `terraform apply`
**Debe verse:** el resumen final con los recursos añadidos.

### `33-terraform-validate.png`
**Comando:** `make tf-validate`
**Debe verse:** ambos entornos validados correctamente.

### `34-terraform-plan-aws.png`
**Dónde:** job `terraform-plan` del workflow CD
**Debe verse:** la validación del código de AWS ejecutándose en el pipeline.

---

## Evidencias textuales automáticas

Además de las capturas:

```bash
make evidencias
```

Genera `evidencias/AAAAMMDD-HHMMSS/` con 15 archivos de texto. Estos sirven
como anexo del informe y respaldan lo que muestran las imágenes.

---

## Lista de verificación final

- [ ] Bloque 1 — Aplicación y contenedor (4 capturas)
- [ ] Bloque 2 — Kubernetes (5 capturas)
- [ ] Bloque 3 — Auto-escalado (4 capturas)
- [ ] Bloque 4 — Monitoreo (6 capturas)
- [ ] Bloque 5 — Pipeline CI/CD (10 capturas)
- [ ] Bloque 6 — FinOps (2 capturas)
- [ ] Bloque 7 — Terraform (3 capturas)
- [ ] Evidencias textuales generadas con `make evidencias`
- [ ] Historial de commits descriptivos en el repositorio

**Total: 34 capturas.** No hacen falta las 34 para aprobar, pero los bloques 3
y 5 son los que más peso tienen: son los que demuestran auto-escalado y pipeline
funcionando, que es el núcleo de lo que se evalúa.

# Decisiones de arquitectura

Registro de las decisiones no obvias del proyecto, con su contexto y sus
consecuencias. El formato es un ADR (Architecture Decision Record) simplificado.

---

## ADR-001 — El entorno ejecutable es un cluster local, no AWS

**Contexto.** La consigna pide definir con Terraform la infraestructura
necesaria, incluyendo redes, instancias y un cluster de Kubernetes, y presentar
evidencias del despliegue funcionando.

**Problema.** Un control plane de EKS cuesta unos US$73 mensuales y no está
cubierto por la capa gratuita de AWS. Sumando nodos EC2 y NAT Gateway, el
entorno ronda los US$120 por mes. Para un proyecto formativo esto implica un
costo real y el riesgo concreto de dejar recursos encendidos por olvido.

**Decisión.** Se implementan dos entornos:

- `terraform/environments/local` provisiona un cluster kind con tres nodos e
  instala la plataforma vía Helm. Es el entorno que se aplica y del que salen
  las evidencias.
- `terraform/environments/aws` compone los módulos `network`, `cluster` y
  `app-registry` con código completo y funcional. Se valida en cada corrida del
  pipeline con `fmt`, `validate`, `plan` y Checkov, pero el `apply` es manual y
  deliberado.

**Consecuencias.** Se demuestra dominio de Terraform sobre recursos cloud reales
(VPC, subnets, NAT, EKS, node groups, IAM, KMS, ECR) sin incurrir en costos. La
API de Kubernetes es idéntica entre kind y EKS, así que los manifiestos, el HPA
y el monitoreo se validan de verdad. Lo que no se ejercita en vivo es la
integración con servicios propios de AWS: balanceadores gestionados, IRSA y
autoescalado de nodos.

---

## ADR-002 — El pipeline levanta su propio cluster efímero

**Contexto.** El análisis DAST requiere una aplicación en ejecución, y la
consigna pide que el pipeline despliegue en Kubernetes.

**Problema.** Un entorno de staging persistente factura las 24 horas aunque se
use unos minutos por día. Pero sin despliegue real no hay DAST real ni evidencia
de que los manifiestos funcionen.

**Decisión.** El job `deploy` del workflow CD crea un cluster kind dentro del
runner de GitHub Actions, instala Ingress Controller y metrics-server, despliega
la aplicación, verifica el rollout, ejecuta smoke tests contra el Ingress y
recolecta evidencias. El cluster se destruye con el runner.

**Consecuencias.** Cada corrida valida el despliegue completo de forma
reproducible y aislada, con costo cero de infraestructura. La contrapartida es
que el job tarda entre 6 y 8 minutos, y que no se prueban comportamientos que
solo aparecen en un cluster cloud real, como el aprovisionamiento de
balanceadores.

---

## ADR-003 — La seguridad se distribuye en capas, no en un único escáner

**Contexto.** La consigna pide análisis SAST y DAST.

**Problema.** SAST y DAST cubren superficies distintas y ninguno de los dos ve
las vulnerabilidades de las dependencias, de la imagen base ni de la
infraestructura. Cumplir el requisito literal con dos herramientas dejaría
huecos evidentes.

**Decisión.** Ocho controles automatizados en momentos distintos del ciclo:
Bandit, Semgrep y CodeQL sobre el código; Dependabot sobre las dependencias;
Hadolint sobre el Dockerfile; Trivy sobre la imagen construida; Checkov sobre
Terraform; y OWASP ZAP sobre la aplicación desplegada.

**Consecuencias.** Cobertura de seguridad considerablemente más amplia que el
mínimo pedido, con todos los hallazgos centralizados en formato SARIF dentro de
la pestaña Security del repositorio. El costo es un pipeline más largo y la
posibilidad de falsos positivos, mitigada configurando `soft_fail` en las
herramientas más ruidosas y reservando el fallo duro para las vulnerabilidades
críticas con corrección disponible.

---

## ADR-004 — El Deployment no fija el número de réplicas

**Contexto.** El Deployment y el HPA pueden ambos controlar el campo `replicas`.

**Problema.** Si el manifiesto del Deployment declara `replicas: 2` y el HPA
escaló a 6, el siguiente `kubectl apply` devuelve el valor a 2 y el HPA vuelve a
subirlo. El resultado es un ciclo de escalado y reducción en cada despliegue.

**Decisión.** El Deployment omite el campo `replicas` por completo. El HPA es el
único dueño de esa propiedad. De forma análoga, el node group de Terraform
declara `ignore_changes` sobre `desired_size`.

**Consecuencias.** Los despliegues no interfieren con el autoescalado. Al crear
el Deployment por primera vez, Kubernetes arranca con una réplica y el HPA la
lleva a `minReplicas` en unos segundos.

---

## ADR-005 — Almacenamiento en memoria y aplicación sin estado

**Contexto.** La aplicación necesita algún tipo de persistencia para tener
sentido funcional.

**Problema.** Una base de datos agrega StatefulSets, volúmenes persistentes,
migraciones y backups. Todo eso desplaza el foco del proyecto, que es el
pipeline, y complica el autoescalado horizontal.

**Decisión.** Almacenamiento en memoria dentro del proceso. La aplicación es
completamente sin estado desde la perspectiva de la infraestructura.

**Consecuencias.** El HPA puede escalar libremente sin coordinación entre
réplicas, y la demostración de auto-escalado es limpia. La limitación evidente
es que cada réplica tiene su propio conjunto de datos y que un reinicio los
pierde; es aceptable porque los datos son de demostración.

---

## ADR-006 — Registry: GHCR en lugar de Docker Hub o ECR

**Contexto.** El pipeline debe publicar imágenes en un registry.

**Problema.** Docker Hub impone límites de descarga en su plan gratuito y
requiere gestionar credenciales. ECR obliga a tener infraestructura AWS
aplicada, que según el ADR-001 no es el caso.

**Decisión.** GitHub Container Registry, autenticado con el `GITHUB_TOKEN`
efímero que GitHub inyecta en cada corrida.

**Consecuencias.** No hay ninguna credencial almacenada en el repositorio y el
registry queda integrado con los permisos del propio proyecto. El módulo de
Terraform para ECR se mantiene igualmente escrito y validado, de modo que migrar
a AWS sea un cambio de configuración y no de arquitectura.

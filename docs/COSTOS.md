# Análisis de costos (FinOps)

Cuantificación del impacto de las medidas de optimización aplicadas. Los precios
corresponden a la región `us-east-1` y son órdenes de magnitud para comparar
configuraciones, no una cotización.

---

## Escenario de referencia

Un entorno de pruebas para una aplicación web con dos réplicas, disponible de
lunes a viernes en horario laboral.

## Comparación

| Componente | Sin optimizar | Optimizado | Ahorro mensual |
|---|---|---|---|
| Control plane EKS | US$73 | US$73 | — |
| Nodos EC2 (2 × t3.small) | US$30 on-demand, 24×7 | US$3 SPOT, 60 h/semana | US$27 |
| NAT Gateway | US$65 (uno por AZ) | US$33 (compartido) | US$32 |
| Balanceadores | US$36 (uno por servicio) | US$18 (un Ingress) | US$18 |
| Almacenamiento ECR | US$5 y creciendo | US$1 con lifecycle | US$4 |
| Logs CloudWatch | US$8 sin retención | US$2 con 7 días | US$6 |
| **Total** | **US$217** | **US$130** | **US$87 (40 %)** |

El control plane de EKS es un costo fijo que no admite optimización: es el
argumento central del ADR-001 a favor del entorno local.

---

## Detalle de cada medida

### Instancias SPOT

Las instancias SPOT usan capacidad ociosa de AWS con descuentos del 70 al 90 %
frente a on-demand. A cambio, AWS puede reclamarlas avisando con dos minutos de
anticipación.

El proyecto asume ese riesgo de forma explícita: el `PodDisruptionBudget`
garantiza al menos una réplica disponible durante el drenado de un nodo, los
`topologySpreadConstraints` reparten las réplicas entre nodos, y el node group
declara varios tipos de instancia (`t3.small` y `t3a.small`) para aumentar la
probabilidad de conseguir capacidad.

En un entorno productivo con SLA estricto, la práctica habitual es una base de
nodos on-demand más una capa elástica en SPOT.

### Apagado programado

Una semana tiene 168 horas. Un entorno de pruebas usado de lunes a viernes de
8 a 20 se utiliza 60. Pagar las 168 significa desperdiciar el 64 % del gasto de
cómputo.

El workflow `finops.yml` escala el node group a cero nodos a las 20:00 y lo
restaura a las 08:00, de lunes a viernes. El control plane sigue facturando,
pero las instancias y sus volúmenes EBS no.

### NAT Gateway compartido

Un NAT Gateway cuesta unos US$0,045 por hora más US$0,045 por GB procesado. La
práctica recomendada para producción es uno por zona de disponibilidad, para que
la caída de una zona no deje sin salida a las demás. En un entorno de pruebas
esa resiliencia no justifica duplicar el costo, así que el módulo `network`
expone la variable `single_nat_gateway` con valor por defecto `true`.

### Un Ingress en lugar de varios Services de tipo LoadBalancer

Cada Service de tipo `LoadBalancer` provisiona un balanceador en AWS, a unos
US$18 mensuales. Con un único Ingress Controller y reglas de enrutamiento por
host o path, N servicios comparten un solo balanceador.

### Ciclo de vida de las imágenes

Cada build del pipeline genera una imagen. Sin política de retención, el
almacenamiento crece de forma indefinida y se paga por GB al mes para siempre.
El módulo `app-registry` conserva las últimas diez imágenes etiquetadas y
elimina las no etiquetadas a los tres días. El workflow de FinOps aplica una
limpieza equivalente en GHCR.

### Requests y limits ajustados

En Kubernetes, `requests` es lo que el planificador reserva: capacidad que se
paga esté o no en uso. Sobredimensionar los requests obliga a mantener más nodos
de los necesarios.

Los valores del proyecto (50m de CPU y 128Mi de memoria como request, con
límites de 300m y 256Mi) surgen de observar el consumo real durante las pruebas
de carga. La regla práctica es fijar el request cerca del percentil 95 del uso
observado y el límite con margen para picos.

**Nota sobre la interacción con el HPA.** El request de memoria arrancó en 64Mi,
pero la aplicación en reposo ya consume ~45Mi (el runtime de Python): eso daba un
uso del ~71%, pegado al objetivo del 75% que usa el HPA para escalar por memoria.
El efecto era que la métrica de memoria "clavaba" el número de réplicas —
`techo(réplicas × 71/75)` siempre redondea al valor actual— e impedía el
*scale-down*: el HPA subía bien ante la carga, pero no volvía a bajar. Subir el
request a 128Mi deja el uso en reposo en ~35% y le devuelve margen a la métrica,
de modo que el HPA reduce réplicas por CPU cuando la demanda cae. Es la tensión
clásica entre FinOps (requests ajustados) y el autoescalado por memoria: el
request tiene que quedar por encima del piso de consumo, no pegado a él.

### Techo del autoescalado

`maxReplicas: 8` no es solo un parámetro de rendimiento: es un límite de gasto.
Sin techo, un pico de tráfico legítimo o un ataque de denegación de servicio
podría escalar hasta agotar el presupuesto. La alerta `TaskApiHpaEnElLimite`
avisa cuando el HPA lleva diez minutos en su máximo, que es la señal de que hay
que revisar si corresponde subir el techo o si existe un problema de fondo.

### Optimización del propio pipeline

GitHub Actions cobra por minuto de runner en repositorios privados. Dos medidas
reducen ese consumo: `concurrency` con `cancel-in-progress` cancela corridas
obsoletas cuando llega un push nuevo, y el caché de capas de Docker acorta los
builds sucesivos.

---

## Etiquetado para atribución de costos

Todos los recursos creados por Terraform llevan las etiquetas `Project`,
`Environment`, `ManagedBy`, `Owner` y `CostCenter`, aplicadas desde el bloque
`default_tags` del provider.

Sin etiquetas, la factura de AWS es un número agregado imposible de auditar. Con
ellas, Cost Explorer permite filtrar el gasto por proyecto, por entorno o por
responsable. El job `reporte-costos` del workflow de FinOps consulta
precisamente eso.

---

## Qué queda fuera del alcance

Medidas que corresponderían a un entorno productivo real y que este proyecto no
implementa:

- **Savings Plans o Reserved Instances**: descuentos de hasta el 72 % a cambio
  de un compromiso de uno o tres años. No aplican a cargas efímeras.
- **Cluster Autoscaler o Karpenter**: escalado de nodos, no solo de Pods. El HPA
  añade réplicas, pero si no hay capacidad en los nodos quedan en `Pending`.
- **Presupuestos y alertas de AWS Budgets**: notificación automática al superar
  un umbral de gasto.
- **Vertical Pod Autoscaler**: recomendación automática de requests y limits a
  partir del consumo histórico.

# =============================================================================
# Atajos de desarrollo y operación.
#   make help   lista todos los objetivos disponibles
# =============================================================================
.DEFAULT_GOAL := help
SHELL := /bin/bash

NAMESPACE  := task-api
CLUSTER    := task-api-local
IMAGEN     := task-api:local
GIT_SHA    := $(shell git rev-parse --short HEAD 2>/dev/null || echo local)

.PHONY: help
help: ## Muestra esta ayuda
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-22s\033[0m %s\n", $$1, $$2}'

# ------------------------------- DESARROLLO ----------------------------------

.PHONY: init
init: ## Instala dependencias de desarrollo y habilita los scripts
	pip install -r requirements-dev.txt
	chmod +x scripts/*.sh

.PHONY: run
run: ## Ejecuta la app localmente con recarga automática
	uvicorn app.main:app --reload --host 0.0.0.0 --port 8000

.PHONY: test
test: ## Ejecuta los tests con cobertura
	pytest

.PHONY: lint
lint: ## Linter y verificación de formato
	ruff check .
	ruff format --check .

.PHONY: format
format: ## Aplica el formateador
	ruff format .
	ruff check --fix .

.PHONY: sast
sast: ## Análisis estático de seguridad local
	bandit -c pyproject.toml -r app/

.PHONY: check
check: lint test sast ## Corre todos los controles de calidad (igual que CI)

# --------------------------------- DOCKER ------------------------------------

.PHONY: build
build: ## Construye la imagen Docker
	docker build -t $(IMAGEN) --build-arg GIT_SHA=$(GIT_SHA) .
	@echo "Tamaño:" && docker images $(IMAGEN) --format "{{.Size}}"

.PHONY: compose-up
compose-up: ## Levanta app + Prometheus + Grafana con Compose
	docker compose up --build -d
	@echo "App        http://localhost:8000/docs"
	@echo "Prometheus http://localhost:9090"
	@echo "Grafana    http://localhost:3000 (admin/admin)"

.PHONY: compose-down
compose-down: ## Detiene el entorno de Compose
	docker compose down -v

# ------------------------------- KUBERNETES ----------------------------------

.PHONY: up
up: ## Levanta el entorno completo en Kubernetes (kind vía Terraform)
	chmod +x scripts/*.sh
	./scripts/setup-local.sh

.PHONY: down
down: ## Destruye el entorno local
	chmod +x scripts/*.sh
	./scripts/teardown.sh

.PHONY: status
status: ## Muestra el estado del despliegue
	kubectl get deploy,pod,svc,ingress,hpa -n $(NAMESPACE) -o wide

.PHONY: logs
logs: ## Sigue los logs de la aplicación
	kubectl logs -n $(NAMESPACE) -l app.kubernetes.io/name=task-api -f --all-containers

.PHONY: grafana
grafana: ## Abre Grafana en localhost:3000
	@echo "http://localhost:3000 (admin/admin)"
	kubectl port-forward -n monitoring svc/monitoring-grafana 3000:80

.PHONY: prometheus
prometheus: ## Abre Prometheus en localhost:9090
	@echo "http://localhost:9090"
	kubectl port-forward -n monitoring svc/monitoring-prometheus 9090:9090

.PHONY: load
load: ## Genera carga para demostrar el autoescalado
	chmod +x scripts/*.sh
	./scripts/load-test.sh

.PHONY: evidencias
evidencias: ## Recolecta evidencias para el informe
	chmod +x scripts/*.sh
	./scripts/evidencias.sh

# -------------------------------- TERRAFORM ----------------------------------

.PHONY: tf-fmt
tf-fmt: ## Formatea el código Terraform
	terraform fmt -recursive terraform/

.PHONY: tf-validate
tf-validate: ## Valida ambos entornos de Terraform
	cd terraform/environments/local && terraform init -backend=false && terraform validate
	cd terraform/environments/aws   && terraform init -backend=false && terraform validate

.PHONY: tf-plan-aws
tf-plan-aws: ## Plan del entorno AWS (requiere credenciales)
	cd terraform/environments/aws && terraform init -backend-config=backend.hcl && terraform plan

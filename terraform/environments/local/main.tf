# =============================================================================
# Entorno: LOCAL (kind)
# Este es el entorno que se aplica de verdad y del que salen las evidencias.
#
# Terraform crea el cluster Kubernetes (kind = Kubernetes IN Docker) e instala
# los componentes de plataforma vía Helm: Ingress Controller, metrics-server
# (requisito del HPA) y el stack Prometheus + Grafana.
#
# Costo: US$0. Provisionamiento completo: ~4 minutos.
# =============================================================================

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    kind = {
      source  = "tehcyx/kind"
      version = "~> 0.5"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30"
    }
  }

  # Estado local: es un entorno efímero y descartable, no requiere backend
  # remoto ni colaboración.
}

# ------------------------------ CLUSTER KIND ---------------------------------

resource "kind_cluster" "this" {
  name           = var.cluster_name
  node_image     = var.node_image
  wait_for_ready = true

  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

    # Nodo de control: expone los puertos 80/443 del host hacia el Ingress.
    node {
      role = "control-plane"

      kubeadm_config_patches = [
        "kind: InitConfiguration\nnodeRegistration:\n  kubeletExtraArgs:\n    node-labels: \"ingress-ready=true\"\n"
      ]

      extra_port_mappings {
        container_port = 80
        host_port      = var.ingress_http_port
        protocol       = "TCP"
      }

      extra_port_mappings {
        container_port = 443
        host_port      = var.ingress_https_port
        protocol       = "TCP"
      }
    }

    # Nodos worker: permiten demostrar de verdad el reparto de réplicas
    # (topologySpreadConstraints) y el comportamiento del HPA.
    dynamic "node" {
      for_each = range(var.worker_count)
      content {
        role = "worker"
      }
    }
  }
}

# ------------------------------- PROVIDERS -----------------------------------

provider "kubernetes" {
  host                   = kind_cluster.this.endpoint
  client_certificate     = kind_cluster.this.client_certificate
  client_key             = kind_cluster.this.client_key
  cluster_ca_certificate = kind_cluster.this.cluster_ca_certificate
}

provider "helm" {
  kubernetes {
    host                   = kind_cluster.this.endpoint
    client_certificate     = kind_cluster.this.client_certificate
    client_key             = kind_cluster.this.client_key
    cluster_ca_certificate = kind_cluster.this.cluster_ca_certificate
  }
}

# --------------------------- INGRESS CONTROLLER ------------------------------

resource "helm_release" "ingress_nginx" {
  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  version          = var.ingress_nginx_version
  namespace        = "ingress-nginx"
  create_namespace = true
  wait             = true
  timeout          = 600

  # Se fija el controller al nodo control-plane, que es el único con los
  # puertos del host mapeados.
  set {
    name  = "controller.nodeSelector.ingress-ready"
    value = "true"
  }

  set {
    name  = "controller.service.type"
    value = "NodePort"
  }

  set {
    name  = "controller.hostPort.enabled"
    value = "true"
  }

  set {
    name  = "controller.tolerations[0].key"
    value = "node-role.kubernetes.io/control-plane"
  }

  set {
    name  = "controller.tolerations[0].operator"
    value = "Exists"
  }

  set {
    name  = "controller.tolerations[0].effect"
    value = "NoSchedule"
  }

  depends_on = [kind_cluster.this]
}

# ------------------------------ METRICS SERVER -------------------------------
# Sin metrics-server el HPA no puede leer el uso de CPU y queda en <unknown>.
# kind no lo trae instalado por defecto.

resource "helm_release" "metrics_server" {
  name             = "metrics-server"
  repository       = "https://kubernetes-sigs.github.io/metrics-server/"
  chart            = "metrics-server"
  version          = var.metrics_server_version
  namespace        = "kube-system"
  wait             = true
  timeout          = 300

  # kind usa certificados de kubelet autofirmados.
  set {
    name  = "args[0]"
    value = "--kubelet-insecure-tls"
  }

  depends_on = [kind_cluster.this]
}

# --------------------------- PROMETHEUS + GRAFANA ----------------------------

resource "helm_release" "monitoring" {
  name             = "monitoring"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  version          = var.kube_prometheus_stack_version
  namespace        = "monitoring"
  create_namespace = true
  wait             = true
  timeout          = 900

  values = [file("${path.module}/values/kube-prometheus-stack.yaml")]

  depends_on = [kind_cluster.this]
}

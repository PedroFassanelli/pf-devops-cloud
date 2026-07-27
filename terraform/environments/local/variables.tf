variable "cluster_name" {
  description = "Nombre del cluster kind."
  type        = string
  default     = "task-api-local"
}

variable "node_image" {
  description = "Imagen del nodo (fija la versión de Kubernetes)."
  type        = string
  default     = "kindest/node:v1.31.0"
}

variable "worker_count" {
  description = "Cantidad de nodos worker además del control-plane."
  type        = number
  default     = 2

  validation {
    condition     = var.worker_count >= 1 && var.worker_count <= 4
    error_message = "worker_count debe estar entre 1 y 4."
  }
}

variable "ingress_http_port" {
  description = "Puerto del host mapeado al 80 del Ingress."
  type        = number
  default     = 8080
}

variable "ingress_https_port" {
  description = "Puerto del host mapeado al 443 del Ingress."
  type        = number
  default     = 8443
}

variable "ingress_nginx_version" {
  description = "Versión del chart de ingress-nginx."
  type        = string
  default     = "4.11.3"
}

variable "metrics_server_version" {
  description = "Versión del chart de metrics-server."
  type        = string
  default     = "3.12.2"
}

variable "kube_prometheus_stack_version" {
  description = "Versión del chart kube-prometheus-stack."
  type        = string
  default     = "65.1.1"
}

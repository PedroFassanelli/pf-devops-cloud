variable "cluster_name" {
  description = "Nombre del cluster EKS."
  type        = string
}

variable "environment" {
  description = "Entorno lógico (dev, staging, prod)."
  type        = string
}

variable "kubernetes_version" {
  description = "Versión de Kubernetes del control plane."
  type        = string
  default     = "1.31"
}

variable "private_subnet_ids" {
  description = "Subnets privadas donde se ubican los nodos."
  type        = list(string)
}

variable "public_subnet_ids" {
  description = "Subnets públicas para los load balancers."
  type        = list(string)
}

variable "capacity_type" {
  description = "Tipo de capacidad de los nodos: ON_DEMAND o SPOT."
  type        = string
  default     = "SPOT"

  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.capacity_type)
    error_message = "capacity_type debe ser ON_DEMAND o SPOT."
  }
}

variable "instance_types" {
  description = "Tipos de instancia del node group. Varios tipos mejoran la disponibilidad de SPOT."
  type        = list(string)
  default     = ["t3.small", "t3a.small"]
}

variable "disk_size" {
  description = "Tamaño del disco de cada nodo en GB."
  type        = number
  default     = 20
}

variable "min_size" {
  description = "Cantidad mínima de nodos."
  type        = number
  default     = 2
}

variable "max_size" {
  description = "Cantidad máxima de nodos (techo de gasto)."
  type        = number
  default     = 4
}

variable "desired_size" {
  description = "Cantidad deseada de nodos al crear el grupo."
  type        = number
  default     = 2
}

variable "endpoint_public_access" {
  description = "Exponer el endpoint de la API de Kubernetes a internet."
  type        = bool
  default     = true
}

variable "public_access_cidrs" {
  description = "CIDRs autorizados a alcanzar el endpoint público de la API."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "log_retention_days" {
  description = "Días de retención de los logs del control plane en CloudWatch."
  type        = number
  default     = 7
}

variable "tags" {
  description = "Tags adicionales."
  type        = map(string)
  default     = {}
}

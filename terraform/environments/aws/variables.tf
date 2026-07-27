variable "aws_region" {
  description = "Región de AWS donde se despliega la infraestructura."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Nombre del proyecto, usado como prefijo de recursos."
  type        = string
  default     = "task-api"
}

variable "environment" {
  description = "Entorno lógico."
  type        = string
  default     = "staging"
}

variable "owner" {
  description = "Responsable de los recursos (tag de gobierno)."
  type        = string
  default     = "equipo-devops"
}

variable "cost_center" {
  description = "Centro de costos para atribución del gasto en Cost Explorer."
  type        = string
  default     = "formacion"
}

variable "vpc_cidr" {
  description = "CIDR de la VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "az_count" {
  description = "Cantidad de zonas de disponibilidad."
  type        = number
  default     = 2
}

variable "kubernetes_version" {
  description = "Versión de Kubernetes."
  type        = string
  default     = "1.31"
}

variable "node_instance_types" {
  description = "Tipos de instancia para los nodos."
  type        = list(string)
  default     = ["t3.small", "t3a.small"]
}

variable "node_min_size" {
  description = "Nodos mínimos."
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Nodos máximos (techo de gasto)."
  type        = number
  default     = 4
}

variable "node_desired_size" {
  description = "Nodos deseados al crear el cluster."
  type        = number
  default     = 2
}

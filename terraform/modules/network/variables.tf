variable "name_prefix" {
  description = "Prefijo aplicado al nombre de todos los recursos."
  type        = string
}

variable "environment" {
  description = "Entorno lógico (dev, staging, prod)."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment debe ser uno de: dev, staging, prod."
  }
}

variable "cluster_name" {
  description = "Nombre del cluster EKS al que se asocian las subnets."
  type        = string
}

variable "vpc_cidr" {
  description = "Rango CIDR de la VPC."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr debe ser un bloque CIDR válido."
  }
}

variable "az_count" {
  description = "Cantidad de zonas de disponibilidad a utilizar."
  type        = number
  default     = 2

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 4
    error_message = "az_count debe estar entre 2 y 4 (EKS requiere al menos 2)."
  }
}

variable "enable_nat_gateway" {
  description = "Crear NAT Gateway para salida a internet desde subnets privadas."
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "Usar un único NAT Gateway compartido (optimización de costos)."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags adicionales para todos los recursos."
  type        = map(string)
  default     = {}
}

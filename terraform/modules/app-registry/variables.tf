variable "repository_name" {
  description = "Nombre del repositorio ECR."
  type        = string
}

variable "environment" {
  description = "Entorno lógico."
  type        = string
}

variable "image_tag_mutability" {
  description = "MUTABLE o IMMUTABLE. IMMUTABLE impide sobrescribir tags ya publicados."
  type        = string
  default     = "IMMUTABLE"

  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.image_tag_mutability)
    error_message = "image_tag_mutability debe ser MUTABLE o IMMUTABLE."
  }
}

variable "keep_last_images" {
  description = "Cantidad de imágenes etiquetadas a conservar (FinOps)."
  type        = number
  default     = 10
}

variable "untagged_expire_days" {
  description = "Días tras los cuales se eliminan las imágenes sin etiqueta."
  type        = number
  default     = 3
}

variable "tags" {
  description = "Tags adicionales."
  type        = map(string)
  default     = {}
}

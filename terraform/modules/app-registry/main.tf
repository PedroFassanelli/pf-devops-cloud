# =============================================================================
# Módulo: app-registry
# Repositorio ECR para las imágenes de la aplicación.
#
# FinOps: sin lifecycle policy, cada build del pipeline deja una imagen que se
# paga por GB/mes para siempre. La política de retención es de las
# optimizaciones con mejor relación esfuerzo/ahorro que existen.
# =============================================================================

locals {
  common_tags = merge(var.tags, {
    Module      = "app-registry"
    Environment = var.environment
    ManagedBy   = "terraform"
  })
}

resource "aws_ecr_repository" "this" {
  name                 = var.repository_name
  image_tag_mutability = var.image_tag_mutability

  image_scanning_configuration {
    # Escaneo de vulnerabilidades en cada push: capa extra de DevSecOps
    # además de Trivy en el pipeline.
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = merge(local.common_tags, {
    Name = var.repository_name
  })
}

resource "aws_ecr_lifecycle_policy" "this" {
  repository = aws_ecr_repository.this.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Conservar solo las ultimas ${var.keep_last_images} imagenes etiquetadas"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v", "sha-", "main"]
          countType     = "imageCountMoreThan"
          countNumber   = var.keep_last_images
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Eliminar imagenes sin etiqueta despues de ${var.untagged_expire_days} dias"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = var.untagged_expire_days
        }
        action = { type = "expire" }
      },
    ]
  })
}

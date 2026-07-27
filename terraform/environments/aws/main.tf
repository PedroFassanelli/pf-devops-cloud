# =============================================================================
# Entorno: AWS (staging)
# Compone los módulos network + cluster + app-registry.
#
# IMPORTANTE: este entorno se valida en el pipeline con `validate` y `plan`,
# pero NO se aplica automáticamente. El `apply` es manual y deliberado porque
# crea recursos facturables (EKS ~US$73/mes de control plane + nodos + NAT).
# =============================================================================

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Estado remoto: permite trabajo colaborativo y evita perder el tfstate.
  # El bucket y la tabla de bloqueo deben existir antes del primer init.
  # Se configura vía `terraform init -backend-config=backend.hcl`.
  backend "s3" {}
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Owner       = var.owner
      # Tag de asignación de costos: permite filtrar el gasto de este
      # proyecto en AWS Cost Explorer (FinOps).
      CostCenter = var.cost_center
    }
  }
}

locals {
  name_prefix  = "${var.project_name}-${var.environment}"
  cluster_name = "${local.name_prefix}-eks"
}

module "network" {
  source = "../../modules/network"

  name_prefix  = local.name_prefix
  environment  = var.environment
  cluster_name = local.cluster_name
  vpc_cidr     = var.vpc_cidr
  az_count     = var.az_count

  # FinOps: un solo NAT Gateway compartido en lugar de uno por AZ.
  single_nat_gateway = true
}

module "registry" {
  source = "../../modules/app-registry"

  repository_name  = var.project_name
  environment      = var.environment
  keep_last_images = 10
}

module "cluster" {
  source = "../../modules/cluster"

  cluster_name       = local.cluster_name
  environment        = var.environment
  kubernetes_version = var.kubernetes_version

  private_subnet_ids = module.network.private_subnet_ids
  public_subnet_ids  = module.network.public_subnet_ids

  # FinOps: instancias SPOT y techo de 4 nodos.
  capacity_type  = "SPOT"
  instance_types = var.node_instance_types
  min_size       = var.node_min_size
  max_size       = var.node_max_size
  desired_size   = var.node_desired_size
}

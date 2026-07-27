output "cluster_name" {
  description = "Nombre del cluster EKS."
  value       = module.cluster.cluster_name
}

output "cluster_endpoint" {
  description = "Endpoint de la API de Kubernetes."
  value       = module.cluster.cluster_endpoint
}

output "kubeconfig_command" {
  description = "Comando para configurar kubectl."
  value       = module.cluster.kubeconfig_command
}

output "ecr_repository_url" {
  description = "URL del repositorio ECR."
  value       = module.registry.repository_url
}

output "vpc_id" {
  description = "ID de la VPC."
  value       = module.network.vpc_id
}

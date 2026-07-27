output "cluster_name" {
  description = "Nombre del cluster EKS."
  value       = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  description = "Endpoint de la API de Kubernetes."
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_ca_certificate" {
  description = "Certificado de la CA del cluster (base64)."
  value       = aws_eks_cluster.this.certificate_authority[0].data
  sensitive   = true
}

output "cluster_version" {
  description = "Versión de Kubernetes desplegada."
  value       = aws_eks_cluster.this.version
}

output "node_group_arn" {
  description = "ARN del node group gestionado."
  value       = aws_eks_node_group.this.arn
}

output "kubeconfig_command" {
  description = "Comando para configurar kubectl contra este cluster."
  value       = "aws eks update-kubeconfig --name ${aws_eks_cluster.this.name}"
}

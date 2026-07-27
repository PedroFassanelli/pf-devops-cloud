output "repository_url" {
  description = "URL del repositorio ECR para docker push."
  value       = aws_ecr_repository.this.repository_url
}

output "repository_arn" {
  description = "ARN del repositorio."
  value       = aws_ecr_repository.this.arn
}

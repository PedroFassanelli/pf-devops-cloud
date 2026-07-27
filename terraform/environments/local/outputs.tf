output "cluster_name" {
  description = "Nombre del cluster kind creado."
  value       = kind_cluster.this.name
}

output "kubeconfig_path" {
  description = "Ruta al kubeconfig generado por kind."
  value       = kind_cluster.this.kubeconfig_path
}

output "app_url" {
  description = "URL de la aplicación a través del Ingress."
  value       = "http://task-api.local:${var.ingress_http_port}"
}

output "grafana_command" {
  description = "Comando para abrir Grafana."
  value       = "kubectl port-forward -n monitoring svc/monitoring-grafana 3000:80"
}

output "prometheus_command" {
  description = "Comando para abrir Prometheus."
  value       = "kubectl port-forward -n monitoring svc/monitoring-kube-prometheus-prometheus 9090:9090"
}

output "hosts_entry" {
  description = "Línea a agregar en /etc/hosts para resolver el Ingress."
  value       = "127.0.0.1 task-api.local"
}

output "cluster_name" {
  description = "GKE cluster name"
  value       = google_container_cluster.primary.name
}

output "cluster_endpoint" {
  description = "GKE cluster API endpoint"
  value       = google_container_cluster.primary.endpoint
  sensitive   = true
}

output "cluster_ca_certificate" {
  description = "Base64-encoded cluster CA certificate"
  value       = google_container_cluster.primary.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "cluster_location" {
  description = "GKE cluster region"
  value       = google_container_cluster.primary.location
}

output "node_service_account" {
  description = "Service account email used by GKE nodes"
  value       = google_service_account.gke_sa.email
}

output "workload_identity_pool" {
  description = "Workload Identity pool for this cluster"
  value       = "${var.project_id}.svc.id.goog"
}

output "crossplane_namespace" {
  description = "Namespace where Crossplane is installed"
  value       = kubernetes_namespace.crossplane_system.metadata[0].name
}

output "get_credentials_command" {
  description = "gcloud command to configure kubectl"
  value       = "gcloud container clusters get-credentials ${google_container_cluster.primary.name} --region ${var.region} --project ${var.project_id}"
}
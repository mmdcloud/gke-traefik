variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region for the cluster"
  type        = string
  default     = "us-central1"
}

variable "cluster_name" {
  description = "Name of the GKE cluster"
  type        = string
  default     = "platform-cluster"
}

variable "network_name" {
  description = "Name of the VPC network"
  type        = string
  default     = "platform-vpc"
}

variable "subnet_name" {
  description = "Name of the subnet"
  type        = string
  default     = "platform-subnet"
}

variable "subnet_cidr" {
  description = "CIDR for the primary subnet"
  type        = string
  default     = "10.0.0.0/20"
}

variable "pods_cidr" {
  description = "Secondary CIDR range for pods"
  type        = string
  default     = "10.1.0.0/16"
}

variable "services_cidr" {
  description = "Secondary CIDR range for services"
  type        = string
  default     = "10.2.0.0/20"
}

variable "master_cidr" {
  description = "CIDR for the GKE master control plane (must be /28)"
  type        = string
  default     = "172.16.0.0/28"
}

# Node pool sizing
variable "system_node_count" {
  description = "Number of nodes in the system node pool (per zone)"
  type        = number
  default     = 1
}

variable "app_node_min" {
  description = "Min nodes for app node pool autoscaler"
  type        = number
  default     = 1
}

variable "app_node_max" {
  description = "Max nodes for app node pool autoscaler"
  type        = number
  default     = 5
}

variable "system_machine_type" {
  description = "Machine type for system node pool"
  type        = string
  default     = "e2-standard-2"
}

variable "app_machine_type" {
  description = "Machine type for app node pool"
  type        = string
  default     = "e2-standard-4"
}

variable "kubernetes_version" {
  description = "GKE Kubernetes version (use RAPID/REGULAR/STABLE channel)"
  type        = string
  default     = "latest"
}

variable "release_channel" {
  description = "GKE release channel: RAPID, REGULAR, or STABLE"
  type        = string
  default     = "REGULAR"
}

# Crossplane config
variable "crossplane_version" {
  description = "Crossplane Helm chart version"
  type        = string
  default     = "1.15.0"
}

variable "crossplane_namespace" {
  description = "Namespace to install Crossplane into"
  type        = string
  default     = "crossplane-system"
}

variable "install_crossplane_provider_aws" {
  description = "Whether to install the Crossplane AWS provider"
  type        = bool
  default     = false
}

variable "install_crossplane_provider_gcp" {
  description = "Whether to install the Crossplane GCP provider"
  type        = bool
  default     = true
}

variable "install_crossplane_provider_helm" {
  description = "Whether to install the Crossplane Helm provider"
  type        = bool
  default     = false
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    managed-by  = "terraform"
    environment = "platform"
  }
}
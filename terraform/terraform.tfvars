# -------------------------------------------------------
# Copy this to terraform.tfvars and fill in your values
# -------------------------------------------------------

project_id   = "your-gcp-project-id"
region       = "us-central1"
cluster_name = "platform-cluster"

# Networking
network_name  = "platform-vpc"
subnet_name   = "platform-subnet"
subnet_cidr   = "10.0.0.0/20"
pods_cidr     = "10.1.0.0/16"
services_cidr = "10.2.0.0/20"
master_cidr   = "172.16.0.0/28"

# Cluster config
release_channel = "REGULAR"

# Node pools
system_machine_type = "e2-standard-2"
system_node_count   = 1

app_machine_type = "e2-standard-4"
app_node_min     = 1
app_node_max     = 5

# Crossplane
crossplane_version  = "1.15.0"
crossplane_namespace = "crossplane-system"

install_crossplane_provider_gcp  = true
install_crossplane_provider_aws  = false  # Set true if managing AWS resources via Crossplane
install_crossplane_provider_helm = false  # Set true if building platform abstractions over Helm

labels = {
  managed-by  = "terraform"
  environment = "platform"
  team        = "platform-engineering"
}
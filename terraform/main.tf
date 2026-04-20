# ------------------------------------------------------------------------
# Networking
# ------------------------------------------------------------------------
resource "google_compute_network" "vpc" {
  name                    = var.network_name
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "subnet" {
  name                     = var.subnet_name
  ip_cidr_range            = var.subnet_cidr
  region                   = var.region
  network                  = google_compute_network.vpc.id
  private_ip_google_access = true # Required for private nodes to reach Google APIs

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = var.pods_cidr
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = var.services_cidr
  }
}

# Cloud Router + NAT — required for private nodes to pull images
resource "google_compute_router" "router" {
  name    = "${var.cluster_name}-router"
  region  = var.region
  network = google_compute_network.vpc.id
}

resource "google_compute_router_nat" "nat" {
  name                               = "${var.cluster_name}-nat"
  router                             = google_compute_router.router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# ------------------------------------------------------------------------
# Service Account for GKE Nodes
# ------------------------------------------------------------------------
resource "google_service_account" "gke_sa" {
  account_id   = "${var.cluster_name}-node-sa"
  display_name = "GKE Node Service Account for ${var.cluster_name}"
}

# Minimal permissions — nodes only need to pull images and write logs/metrics
resource "google_project_iam_member" "gke_sa_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.gke_sa.email}"
}

resource "google_project_iam_member" "gke_sa_metric_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.gke_sa.email}"
}

resource "google_project_iam_member" "gke_sa_monitoring_viewer" {
  project = var.project_id
  role    = "roles/monitoring.viewer"
  member  = "serviceAccount:${google_service_account.gke_sa.email}"
}

resource "google_project_iam_member" "gke_sa_artifactregistry_reader" {
  project = var.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${google_service_account.gke_sa.email}"
}

# ------------------------------------------------------------------------
# GKE Cluster
# ------------------------------------------------------------------------
resource "google_container_cluster" "primary" {
  name     = var.cluster_name
  location = var.region # Regional cluster for HA control plane

  # We manage node pools separately below — default pool must be removed
  remove_default_node_pool = true
  initial_node_count       = 1

  network    = google_compute_network.vpc.id
  subnetwork = google_compute_subnetwork.subnet.id

  # Release channel controls minor version upgrades
  release_channel {
    channel = var.release_channel
  }

  # Private cluster — nodes get no external IPs
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false # Keep master endpoint public but auth-protected
    master_ipv4_cidr_block  = var.master_cidr
  }

  # Authorized networks for master endpoint access
  master_authorized_networks_config {
    cidr_blocks {
      cidr_block   = "0.0.0.0/0"
      display_name = "All (restrict this in production)"
    }
  }

  # VPC-native networking (Alias IP) — required for modern GKE features
  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  # Workload Identity — recommended way to grant pods GCP permissions
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  addons_config {
    # HTTP load balancing — needed for Ingress
    http_load_balancing {
      disabled = false
    }

    # Horizontal Pod Autoscaler
    horizontal_pod_autoscaling {
      disabled = false
    }

    # GCS Fuse CSI driver — useful for ML workloads
    gcs_fuse_csi_driver_config {
      enabled = true
    }

    # Config Connector — optional but useful alongside Crossplane
    config_connector_config {
      enabled = false # Enable if you want Google's own operator instead of Crossplane
    }
  }

  # Binary Authorization — disabled for simplicity, enable for prod
  binary_authorization {
    evaluation_mode = "DISABLED" # Set to PROJECT_SINGLETON_POLICY_ENFORCE for prod
  }

  # Logging and monitoring to Google Cloud Operations
  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
  }

  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS", "STORAGE", "POD", "DEPLOYMENT", "DAEMONSET"]

    managed_prometheus {
      enabled = true # Google Managed Prometheus — zero config scraping
    }
  }

  # Network policy — Calico for pod-to-pod firewall rules
  network_policy {
    enabled  = true
    provider = "CALICO"
  }

  # Disable legacy ABAC — always
  enable_legacy_abac = false

  resource_labels = var.labels

  # Prevent accidental cluster deletion
  deletion_protection = false # Set true in production
}

# ------------------------------------------------------------------------
# System Node Pool — kube-system, crossplane, monitoring components
# ------------------------------------------------------------------------
resource "google_container_node_pool" "system" {
  name     = "system-pool"
  location = var.region
  cluster  = google_container_cluster.primary.name

  # One node per zone in the region for system workloads
  node_count = var.system_node_count

  node_config {
    machine_type = var.system_machine_type
    disk_size_gb = 50
    disk_type    = "pd-ssd"

    service_account = google_service_account.gke_sa.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    # Workload Identity on nodes
    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    # Taint system pool so only system workloads schedule here
    taint {
      key    = "node-role"
      value  = "system"
      effect = "NO_SCHEDULE"
    }

    labels = merge(var.labels, {
      "node-pool" = "system"
    })

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  upgrade_settings {
    max_surge       = 1
    max_unavailable = 0
  }
}

# ------------------------------------------------------------------------
# App Node Pool — application workloads, autoscaled
# ------------------------------------------------------------------------
resource "google_container_node_pool" "apps" {
  name     = "app-pool"
  location = var.region
  cluster  = google_container_cluster.primary.name

  autoscaling {
    min_node_count = var.app_node_min
    max_node_count = var.app_node_max
  }

  node_config {
    machine_type = var.app_machine_type
    disk_size_gb = 100
    disk_type    = "pd-balanced"

    service_account = google_service_account.gke_sa.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    labels = merge(var.labels, {
      "node-pool" = "apps"
    })

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  upgrade_settings {
    max_surge       = 2
    max_unavailable = 0 # Zero-downtime rolling upgrades
  }
}
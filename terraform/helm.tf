# ------------------------------------------------------------------------
# Crossplane Namespace
# ------------------------------------------------------------------------
resource "kubernetes_namespace" "crossplane_system" {
  metadata {
    name = var.crossplane_namespace

    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  depends_on = [
    google_container_node_pool.system,
    google_container_node_pool.apps
  ]
}

# ------------------------------------------------------------------------
# Crossplane — installed via Helm
# Docs: https://docs.crossplane.io/latest/software/install/
# ------------------------------------------------------------------------
resource "helm_release" "crossplane" {
  name       = "crossplane"
  repository = "https://charts.crossplane.io/stable"
  chart      = "crossplane"
  version    = var.crossplane_version
  namespace  = kubernetes_namespace.crossplane_system.metadata[0].name
  set = [
    {
      name  = "args[0]"
      value = "--enable-composition-revisions"
    },
    {
      name  = "args[1]"
      value = "--leader-election"
    },
    {
      name  = "resourcesCrossplane.limits.cpu"
      value = "500m"
    },
    {
      name  = "resourcesCrossplane.limits.memory"
      value = "512Mi"
    },
    {
      name  = "resourcesCrossplane.requests.cpu"
      value = "100m"
    },
    {
      name  = "resourcesCrossplane.requests.memory"
      value = "256Mi"
    },
    {
      name  = "tolerations[0].key"
      value = "node-role"
    },
    {
      name  = "tolerations[0].value"
      value = "system"
    },
    {
      name  = "tolerations[0].effect"
      value = "NoSchedule"
    }
  ]
  wait          = true
  wait_for_jobs = true
  timeout       = 300

  depends_on = [kubernetes_namespace.crossplane_system]
}

# Wait for Crossplane CRDs to be established before installing providers
resource "time_sleep" "wait_for_crossplane" {
  depends_on = [helm_release.crossplane]

  create_duration = "60s"
}

# ------------------------------------------------------------------------
# Crossplane GCP Provider
# Manages GCP resources (Cloud SQL, GCS, Pub/Sub, etc.) from Kubernetes
# ------------------------------------------------------------------------
resource "kubernetes_manifest" "crossplane_provider_gcp" {
  count = var.install_crossplane_provider_gcp ? 1 : 0

  manifest = {
    apiVersion = "pkg.crossplane.io/v1"
    kind       = "Provider"
    metadata = {
      name = "provider-gcp"
    }
    spec = {
      package           = "xpkg.upbound.io/upbound/provider-gcp:v0.41.0"
      packagePullPolicy = "IfNotPresent"
      controllerConfigRef = {
        name = "provider-gcp-config"
      }
    }
  }

  depends_on = [time_sleep.wait_for_crossplane]
}

# ControllerConfig lets us set node affinity / tolerations on provider pods
resource "kubernetes_manifest" "crossplane_provider_gcp_config" {
  count = var.install_crossplane_provider_gcp ? 1 : 0

  manifest = {
    apiVersion = "pkg.crossplane.io/v1alpha1"
    kind       = "ControllerConfig"
    metadata = {
      name = "provider-gcp-config"
    }
    spec = {
      tolerations = [
        {
          key      = "node-role"
          value    = "system"
          effect   = "NoSchedule"
          operator = "Equal"
        }
      ]
      resources = {
        limits = {
          cpu    = "500m"
          memory = "512Mi"
        }
        requests = {
          cpu    = "100m"
          memory = "256Mi"
        }
      }
    }
  }

  depends_on = [time_sleep.wait_for_crossplane]
}

# ------------------------------------------------------------------------
# Crossplane AWS Provider
# Manages AWS resources from Kubernetes (optional)
# ------------------------------------------------------------------------
resource "kubernetes_manifest" "crossplane_provider_aws" {
  count = var.install_crossplane_provider_aws ? 1 : 0

  manifest = {
    apiVersion = "pkg.crossplane.io/v1"
    kind       = "Provider"
    metadata = {
      name = "provider-aws"
    }
    spec = {
      package           = "xpkg.upbound.io/upbound/provider-aws:v0.47.0"
      packagePullPolicy = "IfNotPresent"
      controllerConfigRef = {
        name = "provider-aws-config"
      }
    }
  }

  depends_on = [time_sleep.wait_for_crossplane]
}

resource "kubernetes_manifest" "crossplane_provider_aws_config" {
  count = var.install_crossplane_provider_aws ? 1 : 0

  manifest = {
    apiVersion = "pkg.crossplane.io/v1alpha1"
    kind       = "ControllerConfig"
    metadata = {
      name = "provider-aws-config"
    }
    spec = {
      tolerations = [
        {
          key      = "node-role"
          value    = "system"
          effect   = "NoSchedule"
          operator = "Equal"
        }
      ]
      resources = {
        limits = {
          cpu    = "500m"
          memory = "512Mi"
        }
        requests = {
          cpu    = "100m"
          memory = "256Mi"
        }
      }
    }
  }

  depends_on = [time_sleep.wait_for_crossplane]
}

# ------------------------------------------------------------------------
# Crossplane Helm Provider
# Manages Helm releases as Crossplane managed resources (optional)
# Useful for building platform abstractions over Helm charts
# ------------------------------------------------------------------------
resource "kubernetes_manifest" "crossplane_provider_helm" {
  count = var.install_crossplane_provider_helm ? 1 : 0

  manifest = {
    apiVersion = "pkg.crossplane.io/v1"
    kind       = "Provider"
    metadata = {
      name = "provider-helm"
    }
    spec = {
      package           = "xpkg.upbound.io/crossplane-contrib/provider-helm:v0.18.0"
      packagePullPolicy = "IfNotPresent"
    }
  }

  depends_on = [time_sleep.wait_for_crossplane]
}

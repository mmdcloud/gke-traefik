# ------------------------------------------------------------------------
# Namespace
# ------------------------------------------------------------------------
resource "kubernetes_namespace" "traefik" {
  metadata {
    name = "traefik"
    labels = merge(var.labels, {
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/name"       = "traefik"
    })
  }

  depends_on = [
    google_container_node_pool.system,
    google_container_node_pool.apps,
  ]
}

# ------------------------------------------------------------------------
# Traefik Helm Release
# Chart: traefik/traefik
# Placed on system-pool — ingress controller is a platform component,
# not an app workload. Requires toleration for node-role=system:NoSchedule.
# ------------------------------------------------------------------------
resource "helm_release" "traefik" {
  name             = "traefik"
  repository       = "https://traefik.github.io/charts"
  chart            = "traefik"
  version          = var.traefik_chart_version
  namespace        = kubernetes_namespace.traefik.metadata[0].name
  create_namespace = false
  timeout          = 300
  wait             = true
  wait_for_jobs    = true

  values = [
    yamlencode({

      # -----------------------------------------------------------------------
      # Deployment
      # -----------------------------------------------------------------------
      deployment = {
        replicas = var.traefik_replicas
      }

      # -----------------------------------------------------------------------
      # Node placement — system-pool
      # Toleration mirrors the exact taint on google_container_node_pool.system:
      #   key: node-role, value: system, effect: NoSchedule
      # nodeSelector pins it so it never drifts to app-pool
      # -----------------------------------------------------------------------
      tolerations = [
        {
          key      = "node-role"
          value    = "system"
          operator = "Equal"
          effect   = "NoSchedule"
        }
      ]

      nodeSelector = {
        "node-pool" = "system"
      }

      # Spread replicas across nodes (regional cluster = 3 zones)
      affinity = {
        podAntiAffinity = {
          preferredDuringSchedulingIgnoredDuringExecution = [
            {
              weight = 100
              podAffinityTerm = {
                labelSelector = {
                  matchLabels = {
                    "app.kubernetes.io/name" = "traefik"
                  }
                }
                topologyKey = "kubernetes.io/hostname"
              }
            }
          ]
        }
      }

      # -----------------------------------------------------------------------
      # Resources — sized for e2-medium (2vCPU / 4GB)
      # Traefik is lightweight; 128Mi/256Mi is comfortable at low traffic.
      # -----------------------------------------------------------------------
      resources = {
        requests = {
          cpu    = "100m"
          memory = "128Mi"
        }
        limits = {
          cpu    = "500m"
          memory = "256Mi"
        }
      }

      # -----------------------------------------------------------------------
      # Service — LoadBalancer type gets a GCP L4 external LB
      # This is the correct pattern when GKE http_load_balancing addon is ON:
      # Traefik owns its own LB frontend instead of fighting the GCE ingress
      # controller. The GCE ingress controller handles IngressClass=gce;
      # Traefik handles IngressClass=traefik.
      # -----------------------------------------------------------------------
      service = {
        type = "LoadBalancer"
        annotations = {
          # GCP: provision a regional external LB (same region as cluster)
          "cloud.google.com/load-balancer-type" = "External"
          # Optional: pin to a static IP — create one first with:
          # gcloud compute addresses create traefik-lb-ip --region=us-central1
          # Then uncomment and set the value:
          # "kubernetes.io/ingress.global-static-ip-name" = "traefik-lb-ip"
        }
      }

      # -----------------------------------------------------------------------
      # Ports
      # -----------------------------------------------------------------------
      ports = {
        web = {
          port           = 8000
          exposedPort    = 80
          expose         = { default = true }
          # Redirect all HTTP → HTTPS at the entrypoint level
          redirections = {
            entryPoint = {
              to     = "websecure"
              scheme = "https"
            }
          }
        }
        websecure = {
          port        = 8443
          exposedPort = 443
          expose      = { default = true }
          tls = {
            enabled = true
          }
        }
        # Traefik dashboard — internal only, not exposed via LB
        traefik = {
          port    = 9000
          expose  = { default = false }
        }
        # Metrics port for GKE Managed Prometheus scraping
        metrics = {
          port    = 9100
          expose  = { default = false }
        }
      }

      # -----------------------------------------------------------------------
      # IngressClass — registers traefik as a valid ingressClassName
      # Your cluster has the GCE ingress controller active (http_load_balancing=true)
      # Use ingressClassName: traefik on your Ingress objects to route via Traefik,
      # ingressClassName: gce for the GCE LB if you ever need it.
      # -----------------------------------------------------------------------
      ingressClass = {
        enabled        = true
        isDefaultClass = var.traefik_is_default_ingress_class
        name           = "traefik"
      }

      # -----------------------------------------------------------------------
      # IngressRoute CRDs — Traefik's own routing primitives
      # -----------------------------------------------------------------------
      providers = {
        kubernetesCRD = {
          enabled                   = true
          allowCrossNamespace       = true  # Lets app teams in other ns use IngressRoutes
          allowExternalNameServices = false
        }
        kubernetesIngress = {
          enabled                   = true  # Also handles standard Ingress objects
          allowExternalNameServices = false
          publishedService = {
            enabled = true # Writes LB IP back to Ingress .status.loadBalancer
          }
        }
      }

      # -----------------------------------------------------------------------
      # TLS — cert-manager integration
      # Set traefik_enable_cert_manager = true once cert-manager is installed.
      # Traefik will use ACME/Let's Encrypt via cert-manager ClusterIssuers.
      # -----------------------------------------------------------------------
      certificatesResolvers = var.traefik_enable_cert_manager ? {
        letsencrypt = {
          acme = {
            email   = var.traefik_acme_email
            storage = "/data/acme.json"
            httpChallenge = {
              entryPoint = "web"
            }
          }
        }
      } : {}

      # Persist ACME certs across pod restarts
      persistence = {
        enabled      = var.traefik_enable_cert_manager
        storageClass = "standard-rwo" # GKE default; no SSD needed for cert storage
        size         = "128Mi"
        accessMode   = "ReadWriteOnce"
      }

      # -----------------------------------------------------------------------
      # Dashboard — disabled externally, accessible via kubectl port-forward
      # kubectl -n traefik port-forward svc/traefik 9000:9000
      # -----------------------------------------------------------------------
      dashboard = {
        enabled = var.traefik_dashboard_enabled
      }

      ingressRoute = {
        dashboard = {
          enabled    = var.traefik_dashboard_enabled
          entryPoints = ["traefik"] # Internal port only, never the LB
        }
      }

      # -----------------------------------------------------------------------
      # Metrics — GKE Managed Prometheus is already enabled in the cluster.
      # Traefik exposes /metrics on port 9100; GMP will scrape via PodMonitor.
      # -----------------------------------------------------------------------
      metrics = {
        prometheus = {
          entryPoint = "metrics"
          addEntryPointsLabels = true
          addRoutersLabels     = true
          addServicesLabels    = true
        }
      }

      # -----------------------------------------------------------------------
      # Logs
      # GKE already ships container stdout to Cloud Logging (WORKLOADS component)
      # Just set level; no additional log shipping needed.
      # -----------------------------------------------------------------------
      logs = {
        general = {
          level = "INFO"
        }
        access = {
          enabled = true
          # Structured JSON for Cloud Logging
          format = "json"
          fields = {
            defaultMode = "keep"
            headers = {
              defaultMode = "drop"
              names = {
                Authorization = "drop"
              }
            }
          }
        }
      }

      # -----------------------------------------------------------------------
      # RBAC — needed for Traefik to watch Ingress/IngressRoute/Secret objects
      # -----------------------------------------------------------------------
      rbac = {
        enabled = true
      }

      serviceAccount = {
        create = true
        name   = "traefik"
        # Workload Identity annotation — add if Traefik ever needs GCP API access
        # annotations = {
        #   "iam.gke.io/gcp-service-account" = "traefik@${var.project_id}.iam.gserviceaccount.com"
        # }
      }

      # -----------------------------------------------------------------------
      # Security context — non-root, read-only filesystem
      # -----------------------------------------------------------------------
      securityContext = {
        capabilities = {
          drop = ["ALL"]
          add  = ["NET_BIND_SERVICE"]
        }
        readOnlyRootFilesystem = true
        runAsNonRoot           = true
        runAsUser              = 65532
        runAsGroup             = 65532
      }

      podSecurityContext = {
        fsGroup = 65532
      }

      # -----------------------------------------------------------------------
      # Pod labels for Calico NetworkPolicy selectors
      # -----------------------------------------------------------------------
      podLabels = merge(var.labels, {
        "app.kubernetes.io/name"      = "traefik"
        "app.kubernetes.io/component" = "ingress-controller"
      })

      # -----------------------------------------------------------------------
      # Pod Disruption Budget — keep at least 1 replica up during node upgrades
      # upgrade_settings.max_unavailable = 0 on system-pool makes this extra safe
      # -----------------------------------------------------------------------
      podDisruptionBudget = {
        enabled      = true
        minAvailable = 1
      }

      # -----------------------------------------------------------------------
      # Global args
      # -----------------------------------------------------------------------
      globalArguments = [
        "--global.checknewversion=false",  # No phone-home
        "--global.sendanonymoususage=false"
      ]
    })
  ]

  depends_on = [
    kubernetes_namespace.traefik,
    google_container_node_pool.system,
  ]
}

# ------------------------------------------------------------------------
# PodMonitor — tells GKE Managed Prometheus to scrape Traefik metrics
# GMP is enabled via managed_prometheus { enabled = true } in the cluster.
# This replaces a ServiceMonitor when using GMP's in-cluster collection.
# ------------------------------------------------------------------------
resource "kubernetes_manifest" "traefik_pod_monitor" {
  manifest = {
    apiVersion = "monitoring.googleapis.com/v1"
    kind       = "PodMonitor"
    metadata = {
      name      = "traefik"
      namespace = kubernetes_namespace.traefik.metadata[0].name
      labels    = var.labels
    }
    spec = {
      selector = {
        matchLabels = {
          "app.kubernetes.io/name" = "traefik"
        }
      }
      podMetricsEndpoints = [
        {
          port     = "metrics"
          path     = "/metrics"
          interval = "30s"
        }
      ]
    }
  }

  depends_on = [helm_release.traefik]
}

# ------------------------------------------------------------------------
# NetworkPolicy — Calico is enforced in this cluster.
# Allows: inbound 80/443 from anywhere (internet traffic via LB),
#         inbound 9000 only from kube-system (dashboard port-forward),
#         all egress (Traefik must reach backend services across namespaces).
# ------------------------------------------------------------------------
resource "kubernetes_network_policy" "traefik" {
  metadata {
    name      = "traefik-ingress"
    namespace = kubernetes_namespace.traefik.metadata[0].name
  }

  spec {
    pod_selector {
      match_labels = {
        "app.kubernetes.io/name" = "traefik"
      }
    }

    policy_types = ["Ingress", "Egress"]

    # Allow HTTP/HTTPS from anywhere (GCP LB health checks + real traffic)
    ingress {
      ports {
        port     = "8000"
        protocol = "TCP"
      }
      ports {
        port     = "8443"
        protocol = "TCP"
      }
    }

    # Dashboard — only from kube-system (kubectl port-forward source)
    ingress {
      from {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = "kube-system"
          }
        }
      }
      ports {
        port     = "9000"
        protocol = "TCP"
      }
    }

    # Metrics — only from within the traefik namespace (GMP collector pod)
    ingress {
      from {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = "traefik"
          }
        }
      }
      ports {
        port     = "9100"
        protocol = "TCP"
      }
    }

    # Full egress — Traefik must reach backend services in any namespace
    egress {}
  }

  depends_on = [kubernetes_namespace.traefik]
}
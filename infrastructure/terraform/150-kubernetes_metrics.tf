resource "argocd_application" "kube-prometheus-stack" {
  metadata {
    name      = "kube-prometheus-stack"
    namespace = kubernetes_namespace_v1.argo.id
  }

  spec {
    source {
      repo_url = "https://prometheus-community.github.io/helm-charts"
      chart = "kube-prometheus-stack"
      target_revision = "86.2.2"
      
      helm {
        release_name = "kube-prometheus-stack"
        values = templatefile("${path.module}/helm/templates/metrics.tftpl", {
          dns_zone = var.dns_zone,
          grafana_client_id = var.grafana_client_id,
          grafana_client_secret = var.grafana_client_secret,
        })
      }
    }

    source {
      repo_url        = "git@git.${var.dns_zone}:chloe/homelab.git"
      target_revision = "HEAD"
      path            = "./applications/kube-prometheus-stack"
      ref             = "config"
    }

    destination {
      server    = "https://kubernetes.default.svc"
      namespace = "metrics"
    }

    sync_policy {
      # automated {
      #   prune       = true
      #   self_heal   = true
      #   allow_empty = true
      # }
      sync_options = [
        "ServerSideApply=true",
        "Validate=false",
      ]
      
      retry {
        limit = "3"
        backoff {
          duration     = "30s"
          max_duration = "2m"
          factor       = "2"
        }
      }
    }
  }
}

resource "argocd_application" "oauth2-proxy-metrics-alertmanager" {
  for_each = { for i, v in var.oauth_services_temp_migration : i => v }
  metadata {
    name      = "oauth2-proxy-metrics-alertmanager"
    namespace = kubernetes_namespace_v1.argo.id
  }

  spec {
    source {
      repo_url = "https://oauth2-proxy.github.io/manifests"
      chart = "oauth2-proxy"
      target_revision = "10.4.3"
      
      helm {
        release_name = "oauth2-proxy"
        values = templatefile("${path.module}/helm/templates/oauth2proxy.tftpl", {
          dns_zone = var.dns_zone
          subnet = each.value.subnet
          client_id = each.value.client_id
          client_secret = each.value.client_secret
          roles = each.value.roles
          realm = each.value.realm
          email_domain = var.dns_zone
        })
      }
    }

    destination {
      server    = "https://kubernetes.default.svc"
      namespace = "metrics"
    }

    sync_policy {
      # automated {
      #   prune       = true
      #   self_heal   = true
      #   allow_empty = true
      # }
      sync_options = [
        "ServerSideApply=true",
        "Validate=false",
      ]
      
      retry {
        limit = "3"
        backoff {
          duration     = "30s"
          max_duration = "2m"
          factor       = "2"
        }
      }
    }
  }
}
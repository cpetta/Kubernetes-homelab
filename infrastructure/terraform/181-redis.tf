resource "argocd_application" "redis" {
  metadata {
    name      = "redis"
    namespace = kubernetes_namespace_v1.argo.id
  }

  spec {
    source {
      repo_url = "https://charts.bitnami.com/bitnami"
      chart = "redis"
      target_revision = "27.0.10"
      
      helm {
        release_name = "redis"
        value_files = ["$config/applications/redis/values.yaml"]
      }
    }

    source {
      repo_url        = "git@git.${var.dns_zone}:chloe/homelab.git"
      target_revision = "HEAD"
      path            = "./applications/redis"
      ref             = "config"
    }

    destination {
      server    = "https://kubernetes.default.svc"
      namespace = "redis"
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
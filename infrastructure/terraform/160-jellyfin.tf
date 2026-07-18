resource "argocd_application" "jellyfin" {
  metadata {
    name      = "jellyfin"
    namespace = kubernetes_namespace_v1.argo.id
  }

  spec {
    source {
      repo_url = "https://jellyfin.github.io/jellyfin-helm"
      chart = "jellyfin"
      target_revision = "3.2.0"
      
      helm {
        release_name = "jellyfin"
        value_files = ["$config/applications/jellyfin/values.yaml"]
      }
    }

    source {
      repo_url        = "git@git.${var.dns_zone}:chloe/homelab.git"
      target_revision = "HEAD"
      path            = "./applications/jellyfin"
      ref             = "config"
    }

    destination {
      server    = "https://kubernetes.default.svc"
      namespace = "jellyfin"
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
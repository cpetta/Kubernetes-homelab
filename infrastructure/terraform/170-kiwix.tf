resource "argocd_application" "kiwix" {
  metadata {
    name      = "kiwix"
    namespace = kubernetes_namespace_v1.argo.id
  }

  spec {
    source {
      repo_url        = "git@git.${var.dns_zone}:chloe/homelab.git"
      target_revision = "HEAD"
      path            = "./applications/kiwix"
      ref             = "config"
    }

    destination {
      server    = "https://kubernetes.default.svc"
      namespace = "kiwix"
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
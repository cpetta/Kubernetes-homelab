resource "argocd_application" "keycloak" {
  metadata {
    name      = "keycloak"
    namespace = kubernetes_namespace_v1.argo.id
  }

  spec {
    source {
      repo_url        = "git@git.${var.dns_zone}:chloe/homelab.git"
      target_revision = "HEAD"
      path            = "./applications/keycloak"
      ref             = "config"
    }

    destination {
      server    = "https://kubernetes.default.svc"
      namespace = "keycloak"
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
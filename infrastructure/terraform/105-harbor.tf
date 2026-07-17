#-------------------------------------------------------
# Harbor - Config
#-------------------------------------------------------
locals {
  harbor = {
    version = "1.19.1"
    subnet = "harbor"
  }
}

resource "argocd_application" "harbor" {
  metadata {
    name      = "harbor"
    namespace = kubernetes_namespace_v1.argo.id
  }

  spec {
    source {
      repo_url = "https://helm.goharbor.io"
      chart = "harbor"
      target_revision = local.harbor.version
      
      helm {
        release_name = "harbor"
        value_files = ["$config/applications/openbao/values.yaml"]
      }
    }

    source {
      repo_url        = "git@git.${var.dns_zone}:chloe/homelab.git"
      target_revision = "HEAD"
      path            = "./applications/harbor"
      ref             = "config"
    }

    destination {
      server    = "https://kubernetes.default.svc"
      namespace = "harbor"
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
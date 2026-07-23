resource "argocd_application" "forgejo" {
  metadata {
    name      = "forgejo"
    namespace = kubernetes_namespace_v1.argo.id
  }

  spec {
    source {
      repo_url = "code.forgejo.org/forgejo-helm"
      chart = "forgejo"
      target_revision = "17.1.0"
      
      helm {
        release_name = "forgejo"
        # value_files = ["$config/applications/forgejo/values.yaml"]
        values = templatefile("${path.module}/helm/templates/forgejo.tftpl", {
          pvc    = "forgejo-pvc",
          pvc_size = 10,
          subnet = "git",
          dns_zone = var.dns_zone,
          db_user = var.forgejo_db_username,
          db_pass = var.forgejo_db_password,
          oauth_secret = var.forgejo_oauth_secret,
          replica_count = 1,
        })
      }
    }

    source {
      repo_url        = "git@git.${var.dns_zone}:chloe/homelab.git"
      target_revision = "HEAD"
      path            = "./applications/forgejo"
      ref             = "config"
    }

    destination {
      server    = "https://kubernetes.default.svc"
      namespace = "forgejo"
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
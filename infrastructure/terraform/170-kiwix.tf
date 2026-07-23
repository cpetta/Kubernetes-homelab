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

resource "argocd_application" "oauth2-proxy-kiwix" {
  metadata {
    name      = "kiwix-oauth2-proxy"
    namespace = kubernetes_namespace_v1.argo.id
  }

  spec {
    source {
      repo_url = "https://oauth2-proxy.github.io/manifests"
      chart = "oauth2-proxy"
      target_revision = "10.4.3"
      
      helm {
        release_name = "kiwix-oauth2-proxy"
        value_files = ["$config/applications/oauth2-proxy-kiwix/values.yaml"]
      }
    }

    source {
      repo_url        = "git@git.${var.dns_zone}:chloe/homelab.git"
      target_revision = "HEAD"
      path            = "./applications/oauth2-proxy-kiwix"
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
    ignore_difference {
      kind          = "Secret"
      name          = "kiwix-oauth2-proxy"
      json_pointers = [
        "/data",
        "/metadata/annotations",
      ]
    }
  }
}
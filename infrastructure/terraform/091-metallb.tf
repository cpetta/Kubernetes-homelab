resource "argocd_application" "metal-lb" {
  metadata {
    name      = "metallb"
    namespace = kubernetes_namespace_v1.argo.id
  }

  spec {
    # source {
    #   repo_url = "https://metallb.github.io/metallb"
    #   chart = "metallb"
    #   target_revision = "0.16.1"
      
    #   helm {
    #     release_name = "metallb"
    #   }
    # }
    source {
      repo_url        = "https://github.com/metallb/metallb.git"
      target_revision = "v0.16.1"
      path            = "config/manifests"
      directory {
        recurse = false
      }
    }

    # TODO Establish single source of truth (reconcile this path with terraform/helm/templates/metallb.tftpl)
    source {
      repo_url        = "git@git.${var.dns_zone}:chloe/homelab.git"
      target_revision = "HEAD"
      path            = "./applications/metallb"
      ref             = "config"
    }

    destination {
      server    = "https://kubernetes.default.svc"
      namespace = "metallb-system"
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
      kind = "Configmap"
      name = "metallb-frr-startup"
    }
  }
}
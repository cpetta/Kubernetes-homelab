resource "argocd_application" "traefik" {
  metadata {
    name      = "traefik"
    namespace = kubernetes_namespace_v1.argo.id
  }

  spec {
    source {
      repo_url = "https://traefik.github.io/charts"
      chart = "traefik"
      target_revision = "41.0.0"
      
      helm {
        release_name = "traefik"
        # TODO replace with GitOPs
        values = templatefile("${path.module}/helm/templates/traefik.tftpl", {
          dns_zone             = var.dns_zone,
          admin_email          = var.admin_email,
          password             = var.traefik_password,
          cloudflare_api_email = var.cloudflare_api_email,
          cloudflare_token     = var.cloudflare_token,
        })
      }
    }

    source {
      repo_url        = "git@git.${var.dns_zone}:chloe/homelab.git"
      target_revision = "HEAD"
      path            = "./applications/traefik"
      ref             = "config"
    }

    destination {
      server    = "https://kubernetes.default.svc"
      namespace = "traefik"
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

resource "argocd_application" "oauth2-proxy-traefik" {
  metadata {
    name      = "traefik-oauth2-proxy"
    namespace = kubernetes_namespace_v1.argo.id
  }

  spec {
    source {
      repo_url = "https://oauth2-proxy.github.io/manifests"
      chart = "oauth2-proxy"
      target_revision = "10.4.3"
      
      helm {
        release_name = "traefik-oauth2-proxy"
        value_files = ["$config/applications/oauth2-proxy-traefik/values.yaml"]
      }
    }

    source {
      repo_url        = "git@git.${var.dns_zone}:chloe/homelab.git"
      target_revision = "HEAD"
      path            = "./applications/oauth2-proxy-traefik"
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
    ignore_difference {
      kind          = "Secret"
      name          = "traefik-oauth2-proxy"
      json_pointers = [
        "/data",
        "/metadata/annotations",
      ]
    }
  }
}
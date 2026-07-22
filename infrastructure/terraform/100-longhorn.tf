resource "kubernetes_secret_v1" "backblaze_credentials" {
  type = "Opaque"
  metadata {
    name      = "longhorn-backup-backblaze-credentials"
    namespace = "longhorn-system"
  }

  data = {
     AWS_ENDPOINTS =  "https://s3.us-east-005.backblazeb2.com"
     AWS_ACCESS_KEY_ID = var.backblaze_application_key_ID
     AWS_SECRET_ACCESS_KEY = var.backblaze_application_key_key
  }
}

resource "argocd_application" "longhorn" {
  metadata {
    name      = "longhorn"
    namespace = kubernetes_namespace_v1.argo.id
  }

  spec {
    source {
      repo_url = "https://charts.longhorn.io"
      chart = "longhorn"
      target_revision = "1.12.0"
      
      helm {
        release_name = "longhorn"
        # TODO replace with GitOPs
        values = templatefile("${path.module}/helm/templates/longhorn.tftpl", {
          backupTarget = "s3://chloes-homelab-backups@us-east-005/longhorn"
          backupTargetCredentialSecret = kubernetes_secret_v1.backblaze_credentials.metadata.0.name
        }) 
      }
    }

    source {
      repo_url        = "git@git.${var.dns_zone}:chloe/homelab.git"
      target_revision = "HEAD"
      path            = "./applications/longhorn"
      ref             = "config"
    }

    destination {
      server    = "https://kubernetes.default.svc"
      namespace = "longhorn-system"
    }

    sync_policy {
      automated {
        prune       = true
        self_heal   = true
        allow_empty = true
      }
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


resource "argocd_application" "oauth2-proxy-longhorn" {
  metadata {
    name      = "longhorn-oauth2-proxy"
    namespace = kubernetes_namespace_v1.argo.id
  }

  spec {
    source {
      repo_url = "https://oauth2-proxy.github.io/manifests"
      chart = "oauth2-proxy"
      target_revision = "10.4.3"
      
      helm {
        release_name = "longhorn-oauth2-proxy"
        value_files = ["$config/applications/oauth2-proxy-longhorn/values.yaml"]
      }
    }

    source {
      repo_url        = "git@git.${var.dns_zone}:chloe/homelab.git"
      target_revision = "HEAD"
      path            = "./applications/oauth2-proxy-longhorn"
      ref             = "config"
    }

    destination {
      server    = "https://kubernetes.default.svc"
      namespace = "longhorn-system"
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
      name          = "longhorn-oauth2-proxy"
      json_pointers = [
        "/data",
        "/metadata/annotations",
      ]
    }
  }
}

#-------------------------------------------------------
# HTTP Route (For recovory)
#-------------------------------------------------------
# resource "kubernetes_manifest" "longhorn_dashboard_http_route" {
#   manifest = {
#     apiVersion = "gateway.networking.k8s.io/v1"
#     kind       = "HTTPRoute"
#     metadata = {
#       name      = "longhorn-http-route"
#       namespace = kubernetes_namespace_v1.storage.id
#     }
#     spec = {
#       hostnames = [
#         "longhorn.${var.dns_zone}",
#       ]
#       parentRefs = [
#         {
#           name = "traefik-gateway"
#           namespace = "traefik"
#         },
#       ]
#       rules = [
#         {
#           backendRefs = [
#             {
#               name      = "longhorn-frontend"
#               namespace = kubernetes_namespace_v1.storage.id
#               port      = 80
#             },
#           ]
#           matches = [
#             {
#               path = {
#                 type  = "PathPrefix"
#                 value = "/"
#               }
#             },
#           ]
#         },
#       ]
#     }
#   }
# }
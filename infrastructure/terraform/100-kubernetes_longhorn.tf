locals {
  backup_bucket_name = "chloes-homelab-backups"
}

#-------------------------------------------------------
# Kubernetes - Storage
#-------------------------------------------------------
resource "kubernetes_namespace_v1" "storage" {
  metadata {
    name = "longhorn-system"
    labels = {
      "pod-security.kubernetes.io/enforce"         = "privileged"
      "pod-security.kubernetes.io/enforce-version" = "latest"
      "pod-security.kubernetes.io/audit"           = "privileged"
      "pod-security.kubernetes.io/audit-version"   = "latest"
      "pod-security.kubernetes.io/warn"            = "privileged"
      "pod-security.kubernetes.io/warn-version"    = "latest"
    }
  }
}

resource "kubernetes_secret_v1" "backblaze_credentials" {
  type = "Opaque"
  metadata {
    name      = "longhorn-backup-backblaze-credentials"
    namespace = kubernetes_namespace_v1.storage.id
  }

  data = {
     AWS_ENDPOINTS =  "https://s3.us-east-005.backblazeb2.com"
     AWS_ACCESS_KEY_ID = var.backblaze_application_key_ID
     AWS_SECRET_ACCESS_KEY = var.backblaze_application_key_key
  }
}

resource "helm_release" "longhorn" {
  name              = "longhorn"
  namespace         = kubernetes_namespace_v1.storage.id
  create_namespace  = false
  repository        = "https://charts.longhorn.io"
  chart             = "longhorn"
  version           = "1.12.0"
  values = [
    templatefile("${path.module}/helm/templates/longhorn.tftpl", {
      backupTarget = "s3://${local.backup_bucket_name}@us-east-005/longhorn"
      backupTargetCredentialSecret = kubernetes_secret_v1.backblaze_credentials.metadata.0.name
      subnet = "longhorn"
      dns_zone = var.dns_zone
    })
  ]
}

#-------------------------------------------------------
# Backup Jobs - Level 1
#-------------------------------------------------------
resource "kubernetes_manifest" "snapshot_hourly" {
  manifest = {
    apiVersion = "longhorn.io/v1beta2"
    kind       = "RecurringJob"

    metadata = {
      name      = "snapshot-hourly"
      namespace = kubernetes_namespace_v1.storage.id
    }

    spec = {
      concurrency = 1
      cron        = "0 * * * ?"
      groups      = ["level-1"]
      labels      = {}
      name   = "daily-backup"
      retain = 24
      task   = "backup"
    }
  }
}

resource "kubernetes_manifest" "backup_incremental_daily" {
  manifest = {
    apiVersion = "longhorn.io/v1beta2"
    kind       = "RecurringJob"

    metadata = {
      name      = "backup-daily"
      namespace = kubernetes_namespace_v1.storage.id
    }

    spec = {
      concurrency = 1
      cron        = "0 0 * * ?"
      groups      = ["level-1"]
      labels      = {}
      name   = "backup-daily"
      retain = 7
      task   = "backup"
    }
  }
}

resource "kubernetes_manifest" "backup_full_weekly" {
  manifest = {
    apiVersion = "longhorn.io/v1beta2"
    kind       = "RecurringJob"

    metadata = {
      name      = "full-backup-weekly"
      namespace = kubernetes_namespace_v1.storage.id
    }

    spec = {
      concurrency = 1
      cron        = "0 0 ? * FRI"
      groups      = ["level-1"]
      labels      = {}

      parameters = {
        "full-backup-interval" = "1"
      }

      name   = "full-backup-weekly"
      retain = 4
      task   = "backup"
    }
  }
}

#-------------------------------------------------------
# Backup Jobs - Level 2
#-------------------------------------------------------
resource "kubernetes_manifest" "backup_full_monthly" {
  manifest = {
    apiVersion = "longhorn.io/v1beta2"
    kind       = "RecurringJob"

    metadata = {
      name      = "full-backup-monthly"
      namespace = kubernetes_namespace_v1.storage.id
    }

    spec = {
      concurrency = 1
      cron        = "0 0 1 * ?"
      groups      = ["level-2"]
      labels      = {}

      parameters = {
        "full-backup-interval" = "1"
      }

      name   = "full-backup-monthly"
      retain = 1
      task   = "backup"
    }
  }
}

#-------------------------------------------------------
# HTTP Route and ReferenceGrant - (For recovory)
#-------------------------------------------------------
# resource "kubernetes_manifest" "longhorn_dashboard_http_route" {
#   manifest = {
#     apiVersion = "gateway.networking.k8s.io/v1"
#     kind       = "HTTPRoute"
#     metadata = {
#       name      = "longhorn-http-route"
#       namespace = kubernetes_namespace_v1.traefik.id
#     }
#     spec = {
#       hostnames = [
#         "longhorn.${var.dns_zone}",
#       ]
#       parentRefs = [
#         {
#           name = "traefik-gateway"
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

# resource "kubernetes_manifest" "referencegrant_longhorn_dashboard" {
#   manifest = {
#     apiVersion = "gateway.networking.k8s.io/v1beta1"
#     kind       = "ReferenceGrant"
#     metadata = {
#       name      = "longhorn-reference-grant"
#       namespace = kubernetes_namespace_v1.storage.id
#     }
#     spec = {
#       from = [
#         {
#           group     = "gateway.networking.k8s.io"
#           kind      = "HTTPRoute"
#           namespace = kubernetes_namespace_v1.traefik.id
#         },
#       ]
#       to = [
#         {
#           group     = ""
#           kind      = "Service"
#           name      = "longhorn-frontend"
#           namespace = kubernetes_namespace_v1.storage.id
#         },
#       ]
#     }
#   }
# }
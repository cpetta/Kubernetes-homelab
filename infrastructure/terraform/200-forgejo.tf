#-------------------------------------------------------
# Forgejo - Config
#-------------------------------------------------------
locals {
  forgejo = {
    version = "17.1.0"
    storage = {
      volume_name = "forgejo-7b2708b0"
      size = 10 // Gi
    }
    subnet = "git"
  }
}

resource "kubernetes_namespace_v1" "forgejo" {
  metadata {
    name = "forgejo"
    labels = {
      "pod-security.kubernetes.io/enforce"         = "privileged"
    }
  }
}

#-------------------------------------------------------
# Forgejo - Storage Volume
#-------------------------------------------------------
// Recovered from backup
# resource "kubernetes_manifest" "forgejo_longhorn_volume" {
#   depends_on = [argocd_application.longhorn]
#   manifest = {
#     apiVersion = "longhorn.io/v1beta2"
#     kind       = "Volume"

#     metadata = {
#       name      = "forgejo"
#       namespace = "longhorn-system"
#     }

#     spec = {
#       size             = "${tostring(local.forgejo.storage.size * 1073741824)}" // size Gi in bytes
#       numberOfReplicas = 2
#       frontend         = "blockdev"
#       accessMode       = "rwo"
#       dataLocality     = "disabled"
#     }
#   }
# }

resource "kubernetes_persistent_volume_v1" "forgejo" {
  # depends_on = [kubernetes_manifest.forgejo_longhorn_volume] // Uncomment when not using backup
  metadata {
    name = "forgejo"
  }

  spec {
    storage_class_name = "longhorn"
    access_modes       = ["ReadWriteOnce"]

    capacity = {
      storage = "${local.forgejo.storage.size}Gi"
    }

    persistent_volume_source {
      csi {
        driver        = "driver.longhorn.io"
        volume_handle = local.forgejo.storage.volume_name
        # volume_handle = kubernetes_manifest.forgejo_longhorn_volume.manifest.metadata.name
      }
    }
  }
  lifecycle {
    ignore_changes = [
      metadata
    ]
  }
}

resource "kubernetes_persistent_volume_claim_v1" "forgejo" {
  depends_on = [kubernetes_persistent_volume_v1.forgejo]
  metadata {
    name      = "forgejo-pvc"
    namespace = kubernetes_namespace_v1.forgejo.id
    labels = {
      "recurring-job-group.longhorn.io/level-1" = "enabled"
    }
  }
  spec {
    volume_name = kubernetes_persistent_volume_v1.forgejo.metadata.0.name
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "${local.forgejo.storage.size}Gi"
      }
    }
  }
}

#-------------------------------------------------------
# Forgejo - Helm & Config
#-------------------------------------------------------
# https://code.forgejo.org/forgejo-helm/forgejo-helm
resource "helm_release" "forgejo" {
  depends_on        = [kubernetes_persistent_volume_claim_v1.forgejo]
  name              = "forgejo"
  namespace         = kubernetes_namespace_v1.forgejo.id
  create_namespace  = false
  repository        = "oci://code.forgejo.org/forgejo-helm"
  chart             = "forgejo"
  version           = local.forgejo.version
  dependency_update = true
  values = [
    templatefile("${path.module}/helm/templates/forgejo.tftpl", {
      pvc    = kubernetes_persistent_volume_claim_v1.forgejo.metadata.0.name,
      pvc_size = local.forgejo.storage.size,
      subnet = local.forgejo.subnet,
      dns_zone = var.dns_zone,
      db_user = var.forgejo_db_username,
      db_pass = var.forgejo_db_password,
      oauth_secret = var.forgejo_oauth_secret,
      replica_count = 1,
    })
  ]
}

resource "argocd_application" "forgejo" {
  metadata {
    name      = "forgejo"
    namespace = kubernetes_namespace_v1.argo.id
  }

  spec {
    source {
      repo_url = "oci://code.forgejo.org/forgejo-helm"
      chart = "forgejo"
      target_revision = "17.1.0"
      
      helm {
        release_name = "forgejo"
        # value_files = ["$config/applications/forgejo/values.yaml"]
        values = templatefile("${path.module}/helm/templates/forgejo.tftpl", {
          pvc    = kubernetes_persistent_volume_claim_v1.forgejo.metadata.0.name,
          pvc_size = local.forgejo.storage.size,
          subnet = local.forgejo.subnet,
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
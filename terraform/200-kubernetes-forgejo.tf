#-------------------------------------------------------
# Forgejo - Config
#-------------------------------------------------------
locals {
  forgejo = {
    version = "17.1.0"
    storage = {
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
resource "kubernetes_manifest" "forgejo_longhorn_volume" {
  depends_on = [helm_release.longhorn]
  manifest = {
    apiVersion = "longhorn.io/v1beta2"
    kind       = "Volume"

    metadata = {
      name      = "forgejo"
      namespace = "longhorn-system"
    }

    spec = {
      size             = "${tostring(local.forgejo.storage.size * 1073741824)}" // size Gi in bytes
      numberOfReplicas = 2
      frontend         = "blockdev"
      accessMode       = "rwo"
      dataLocality     = "disabled"
    }
  }
}

resource "kubernetes_persistent_volume_v1" "forgejo" {
  depends_on = [kubernetes_manifest.forgejo_longhorn_volume]
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
        volume_handle = kubernetes_manifest.forgejo_longhorn_volume.manifest.metadata.name
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
  depends_on = [kubernetes_persistent_volume_v1.jellyfin_config]
  metadata {
    name      = "forgejo-pvc"
    namespace = kubernetes_namespace_v1.forgejo.id
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
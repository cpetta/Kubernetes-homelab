#-------------------------------------------------------
# Harbor - Config
#-------------------------------------------------------
locals {
  harbor = {
    version = "1.19.1"
    subnet = "harbor"
    volumes = {
      registry = {
        volume_name = "harbor-registry"
        size = 5 // Gi
        replicas = 3
      }
      jobservice = {
        volume_name = "harbor-jobservice"
        size = 1 // Gi
        replicas = 3
      }
      trivy = {
        volume_name = "harbor-trivy"
        size = 1 // Gi
        replicas = 3
      }
    }
  }
}

#-------------------------------------------------------
# Harbor - Namespace
#-------------------------------------------------------
resource "kubernetes_namespace_v1" "harbor" {
  metadata {
    name = "harbor"
    labels = {
      "pod-security.kubernetes.io/enforce" = "privileged"
    }
  }
}

#-------------------------------------------------------
# Harbor - Secrets
#-------------------------------------------------------
resource "kubernetes_secret_v1" "harbor_admin_password" {
  type = "Opaque"
  metadata {
    name      = "harbor-admin-password"
    namespace = kubernetes_namespace_v1.harbor.id
  }
  data = {
    password = var.harbor_admin_password
  }
}

resource "kubernetes_secret_v1" "harbor_nginx" {
  type = "Opaque"
  metadata {
    name      = "harbor-nginx"
    namespace = kubernetes_namespace_v1.harbor.id
  }
  data = {
    placeholder = ""
  }
}

#-------------------------------------------------------
# Harbor - Volumes
#-------------------------------------------------------
resource "kubernetes_manifest" "harbor_longhorn_volume" {
  depends_on = [helm_release.longhorn]
  for_each   = { for i, v in local.harbor.volumes : i => v }
  manifest = {
    apiVersion = "longhorn.io/v1beta2"
    kind       = "Volume"

    metadata = {
      name      = each.value.volume_name
      namespace = "longhorn-system"
    }

    spec = {
      size             = "${tostring(each.value.size * 1073741824)}" // size Gi in bytes
      numberOfReplicas = each.value.replicas
      frontend         = "blockdev"
      accessMode       = "rwo"
      dataLocality     = "disabled"
    }
  }
}

resource "kubernetes_persistent_volume_v1" "harbor" {
  depends_on = [kubernetes_manifest.harbor_longhorn_volume]
  for_each   = { for i, v in local.harbor.volumes : i => v }
  metadata {
    name = each.value.volume_name
  }

  spec {
    storage_class_name = "longhorn"
    access_modes       = ["ReadWriteOnce"]

    capacity = {
      storage = "${each.value.size}Gi"
    }

    persistent_volume_source {
      csi {
        driver        = "driver.longhorn.io"
        volume_handle = each.value.volume_name
      }
    }
  }
  lifecycle {
    ignore_changes = [
      metadata
    ]
  }
}

resource "kubernetes_persistent_volume_claim_v1" "harbor" {
  depends_on = [kubernetes_persistent_volume_v1.harbor]
  for_each   = { for i, v in local.harbor.volumes : i => v }
  metadata {
    name      = "harbor-${each.key}-pvc"
    namespace = kubernetes_namespace_v1.harbor.id
  }
  spec {
    volume_name = each.value.volume_name
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "${each.value.size}Gi"
      }
    }
  }
}

#-------------------------------------------------------
# Harbor - Helm Chart
#-------------------------------------------------------
resource "helm_release" "harbor" {
  name              = "harbor"
  namespace         = kubernetes_namespace_v1.harbor.id
  create_namespace  = false
  repository        = "https://helm.goharbor.io"
  chart             = "harbor"
  version           = local.harbor.version

  values = [
    jsonencode(yamldecode(templatefile("${path.module}/helm/templates/harbor.tftpl", {
      subnet         = local.harbor.subnet,
      dns_zone       = var.dns_zone,
      pvc_registry   = "${local.harbor.volumes.registry.volume_name}-pvc"
      pvc_jobservice = "${local.harbor.volumes.jobservice.volume_name}-pvc"
      pvc_trivy      = "${local.harbor.volumes.trivy.volume_name}-pvc"
      db_password    = var.harbor_db_password
    })))
  ]
}

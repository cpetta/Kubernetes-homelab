#-------------------------------------------------------
# Kubernetes - PostGreSQL
#-------------------------------------------------------
locals {
  postgresql_volumes = {
    postgresql_primary = {
      name = "postgresql-primary"
      size = 10
      replicas = 1
    }
  }
}

resource "kubernetes_namespace_v1" "postgresql" {
  metadata {
    name = "postgresql-database"
    labels = {}
  }
}

resource "kubernetes_secret_v1" "postgres_password" {
  metadata {
    name      = "postgres-password"
    namespace = kubernetes_namespace_v1.postgresql.id
  }

  data = {
    password          = var.postgress_password
    postgres-password = var.postgress_password
  }

  type = "Opaque"
}

#-------------------------------------------------------
# PostGreSQL - Storage
#-------------------------------------------------------
resource "kubernetes_manifest" "postgres_longhorn_volume" {
  for_each   = { for i, v in local.postgresql_volumes : i => v }
  depends_on = [helm_release.longhorn]
  manifest = {
    apiVersion = "longhorn.io/v1beta2"
    kind       = "Volume"

    metadata = {
      name      = each.value.name
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

resource "kubernetes_persistent_volume_v1" "postgres" {
  depends_on = [kubernetes_manifest.postgres_longhorn_volume]
  for_each   = { for i, v in local.postgresql_volumes : i => v }
  metadata {
    name = each.value.name
    labels = {
      "app.kubernetes.io/name" = each.value.name
    }
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
        volume_handle = kubernetes_manifest.postgres_longhorn_volume[each.key].manifest.metadata.name
      }
    }
  }
  lifecycle {
    ignore_changes = [
      metadata
    ]
  }
}

resource "kubernetes_persistent_volume_claim_v1" "postgres" {
  depends_on = [kubernetes_persistent_volume_v1.postgres]
  for_each   = { for i, v in local.postgresql_volumes : i => v }
  metadata {
    name      = "${each.value.name}-pvc"
    namespace = kubernetes_namespace_v1.postgresql.id
  }
  spec {
    volume_name  = kubernetes_persistent_volume_v1.postgres[each.key].metadata.0.name
    access_modes = ["ReadWriteOnce"]

    resources {
      requests = {
        storage = "${each.value.size}Gi"
      }
    }
  }
}

#-------------------------------------------------------
# Metrics - Helm & Config
#-------------------------------------------------------
resource "helm_release" "postgresql" {
  depends_on = [kubernetes_persistent_volume_claim_v1.postgres]
  name             = "postgresql"
  namespace        = kubernetes_namespace_v1.postgresql.id
  create_namespace = false
  repository       = "https://charts.bitnami.com/bitnami"
  chart            = "postgresql"
  version          = "18.6.6"

  set = [
    {
      name  = "volumePermissions.enabled"
      value = "true"
    }
  ]

  values = [
    jsonencode(yamldecode(templatefile("${path.module}/helm/templates/postgresql.tftpl", {})))
  ]
}
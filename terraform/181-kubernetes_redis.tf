#-------------------------------------------------------
# Kubernetes - Redis
#-------------------------------------------------------
locals {
  redis = {
    volumes = {
      primary = {
          volume_name = "redis-primary"
          name = "redis-primary"
          size = 10
          replicas = 2
      }
      replica = {
          volume_name = "redis-replica"
          name = "redis-replica"
          size = 10
          replicas = 2
      }
    }
  }
}

resource "kubernetes_namespace_v1" "redis" {
  metadata {
    name = "redis"
    labels = {}
  }
}

#-------------------------------------------------------
# Redis - Secrets
#-------------------------------------------------------
resource "kubernetes_secret_v1" "redis_password" {
  metadata {
    name      = "redis-password"
    namespace = kubernetes_namespace_v1.redis.id
  }

  data = {
    password       = var.redis_password
    redis-password = var.redis_password
  }

  type = "Opaque"
}

resource "kubernetes_secret_v1" "redis_password_nextcloud" {
  metadata {
    name      = "redis-config"
    namespace = kubernetes_namespace_v1.nextcloud.id
  }

  data = {
    host           = "redis.redis.svc.cluster.local"
    redis-password = var.redis_password
  }

  type = "Opaque"
}

resource "kubernetes_secret_v1" "redis_secrets_oauth2proxy" {
  metadata {
    name      = "redis-config"
    namespace = kubernetes_namespace_v1.traefik.id
  }

  data = {
    host           = "redis.redis.svc.cluster.local"
    redis-password = var.redis_password
  }

  type = "Opaque"
}

#-------------------------------------------------------
# Redis - Storage
#-------------------------------------------------------
resource "kubernetes_manifest" "redis_longhorn_volume" {
  depends_on = [helm_release.longhorn]
  for_each   = { for i, v in local.redis.volumes : i => v }
  manifest = {
    apiVersion = "longhorn.io/v1beta2"
    kind       = "Volume"

    metadata = {
     # name      = each.value.name
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

resource "kubernetes_persistent_volume_v1" "redis" {
  depends_on = [kubernetes_manifest.redis_longhorn_volume]
  for_each   = { for i, v in local.redis.volumes : i => v }
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

resource "kubernetes_persistent_volume_claim_v1" "redis" {
  depends_on = [kubernetes_persistent_volume_v1.redis]
  for_each   = { for i, v in local.redis.volumes : i => v }
  metadata {
    name      = "${each.value.name}-pvc"
    namespace = kubernetes_namespace_v1.redis.id
  }
  spec {
    volume_name  = kubernetes_persistent_volume_v1.redis[each.key].metadata.0.name
    access_modes = ["ReadWriteOnce"]

    resources {
      requests = {
        storage = "${each.value.size}Gi"
      }
    }
  }
}

#-------------------------------------------------------
# Redis - Helm & Config
#-------------------------------------------------------
resource "helm_release" "redis" {
  depends_on = [kubernetes_persistent_volume_claim_v1.redis]
  name             = "redis"
  namespace        = kubernetes_namespace_v1.redis.id
  create_namespace = false
  repository       = "https://charts.bitnami.com/bitnami"
  chart            = "redis"
  version          = "27.0.10"

  values = [
    jsonencode(yamldecode(templatefile("${path.module}/helm/templates/redis.tftpl", {
        pvc_master = "${local.redis.volumes.primary.name}-pvc"
        pvc_replica = "${local.redis.volumes.replica.name}-pvc"
    })))
  ]
}
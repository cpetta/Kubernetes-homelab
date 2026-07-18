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
# Redis - Storage
#-------------------------------------------------------
resource "kubernetes_manifest" "redis_longhorn_volume" {
  depends_on = [argocd_application.longhorn]
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

resource "argocd_application" "redis" {
  metadata {
    name      = "redis"
    namespace = kubernetes_namespace_v1.argo.id
  }

  spec {
    source {
      repo_url = "https://charts.bitnami.com/bitnami"
      chart = "redis"
      target_revision = "27.0.10"
      
      helm {
        release_name = "redis"
        value_files = ["$config/applications/redis/values.yaml"]
      }
    }

    source {
      repo_url        = "git@git.${var.dns_zone}:chloe/homelab.git"
      target_revision = "HEAD"
      path            = "./applications/redis"
      ref             = "config"
    }

    destination {
      server    = "https://kubernetes.default.svc"
      namespace = "redis"
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
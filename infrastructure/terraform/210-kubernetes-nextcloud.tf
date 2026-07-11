#-------------------------------------------------------
# nextcloud - Config
#-------------------------------------------------------
locals {
  nextcloud = {
    version = "9.1.0"
    storage = {
        config = {
            volume_name = "nextcloud-config-633e928f"
            size = 10 // Gi
            replicas = 3
        }
        data = {
            volume_name = "nextcloud-data-6bda8424"
            size = 100 // Gi
            replicas = 3
        }
    }
    subnet = "drive"
  }
  collabora = {
    subnet = "collabora"
  }
}

resource "kubernetes_namespace_v1" "nextcloud" {
  metadata {
    name = "nextcloud"
    labels = {
        "pod-security.kubernetes.io/enforce" = "privileged" // Only required for NFS
    }
  }
}

#-------------------------------------------------------
# nextcloud - Reverse Proxy configuration secrets
#-------------------------------------------------------
resource "kubernetes_secret_v1" "nextcloud_trusted_proxies" {
  type = "Opaque"
  metadata {
    name      = "nextcloud-trusted-proxies"
    namespace = kubernetes_namespace_v1.nextcloud.id
  }
  data = {
    proxy_list = "192.168.0.240 10.106.52.40 10.0.0.0/8"
  }
}

resource "kubernetes_secret_v1" "nextcloud_overwritehost" {
  type = "Opaque"
  metadata {
    name      = "overwritehost"
    namespace = kubernetes_namespace_v1.nextcloud.id
  }
  data = {
    overwritehost = "${local.nextcloud.subnet}.${var.dns_zone}"
  }
}

resource "kubernetes_secret_v1" "nextcloud_overwriteprotocol" {
  type = "Opaque"
  metadata {
    name      = "overwriteprotocol"
    namespace = kubernetes_namespace_v1.nextcloud.id
  }
  data = {
    overwriteprotocol = "https"
  }
}

resource "kubernetes_secret_v1" "nextcloud_overwritewebroot" {
  type = "Opaque"
  metadata {
    name      = "overwritewebroot"
    namespace = kubernetes_namespace_v1.nextcloud.id
  }
  data = {
    overwritewebroot = "${local.nextcloud.subnet}.${var.dns_zone}"
  }
}

resource "kubernetes_secret_v1" "collabora_login" {
  type = "Opaque"
  metadata {
    name      = "collabora-login"
    namespace = kubernetes_namespace_v1.nextcloud.id
  }
  data = {
    username = "admin"
    password = "admin"
  }
}

#-------------------------------------------------------
# nextcloud - Storage Volumes
#-------------------------------------------------------
# resource "kubernetes_manifest" "nextcloud_longhorn_volume" {
#   for_each   = { for i, v in local.nextcloud.storage : i => v }
#   depends_on = [helm_release.longhorn]
#   manifest = {
#     apiVersion = "longhorn.io/v1beta2"
#     kind       = "Volume"

#     metadata = {
#       name      = "nextcloud-${each.key}"
#       namespace = "longhorn-system"
#     }

#     spec = {
#       size             = "${tostring(local.nextcloud.storage[each.key].size * 1073741824)}" // size Gi in bytes
#       numberOfReplicas = each.value.replicas
#       frontend         = "blockdev"
#       accessMode       = "rwo"
#       dataLocality     = "disabled"
#     }
#   }
# }

resource "kubernetes_persistent_volume_v1" "nextcloud" {
  for_each   = { for i, v in local.nextcloud.storage : i => v }
  # depends_on = [kubernetes_manifest.nextcloud_longhorn_volume]
  metadata {
    name = "nextcloud-${each.key}"
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
        # volume_handle = kubernetes_manifest.nextcloud_longhorn_volume[each.key].manifest.metadata.name
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

resource "kubernetes_persistent_volume_claim_v1" "nextcloud" {
  for_each   = { for i, v in local.nextcloud.storage : i => v }
  depends_on = [kubernetes_persistent_volume_v1.nextcloud]
  metadata {
    name      = "nextcloud-${each.key}-pvc"
    namespace = kubernetes_namespace_v1.nextcloud.id
  }
  spec {
    volume_name = kubernetes_persistent_volume_v1.nextcloud[each.key].metadata.0.name
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "${each.value.size}Gi"
      }
    }
  }
}

#-------------------------------------------------------
# nextcloud - Middleware - auth headers
#-------------------------------------------------------
resource "kubernetes_manifest" "traefik_middleware_nextcloud_redirect" {
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind = "Middleware"
    metadata = {
      name = "nextcloud-redirect"
      namespace = kubernetes_namespace_v1.traefik.id
    }
    spec = {
      redirectRegex = {
        permanent = true
        regex = "^https://(.*)/\\.well-known/(?:card|cal)dav"
        replacement = "https://${1}/remote.php/dav"
      }
    }
  }
}

resource "kubernetes_manifest" "traefik_middleware_nextcloud_headers" {
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind = "Middleware"
    metadata = {
      name = "nextcloud-headers"
      namespace = kubernetes_namespace_v1.traefik.id
    }
    spec = {
      headers = {
        browserXssFilter      = true
        contentTypeNosniff    = true
        customFrameOptionsValue = "SAMEORIGIN"
        forceSTSHeader        = true
        frameDeny             = false
        referrerPolicy        = "same-origin"
        stsIncludeSubdomains  = true
        stsPreload            = true
        stsSeconds            = 15552000
        hostsProxyHeaders = [
            "X-Forwarded-Host"
        ]
        customResponseHeaders = {
          "X-Permitted-Cross-Domain-Policies" = "none"
          "X-Robots-Tag"                      = "noindex, nofollow"
        }
      }
    }
  }
}

#-------------------------------------------------------
# nextcloud - Helm & Config
#-------------------------------------------------------
# https://artifacthub.io/packages/helm/nextcloud/nextcloud
resource "helm_release" "nextcloud" {
  depends_on        = [kubernetes_persistent_volume_claim_v1.nextcloud]
  name              = "nextcloud"
  namespace         = kubernetes_namespace_v1.nextcloud.id
  create_namespace  = false
  repository        = "https://nextcloud.github.io/helm/"
  chart             = "nextcloud"
  version           = local.nextcloud.version
  dependency_update = true
  values = [
    templatefile("${path.module}/helm/templates/nextcloud.tftpl", {
      pvc_config = kubernetes_persistent_volume_claim_v1.nextcloud["config"].metadata.0.name,
      pvc_storage = kubernetes_persistent_volume_claim_v1.nextcloud["data"].metadata.0.name,
      subnet = local.nextcloud.subnet,
      collabora_subnet = local.collabora.subnet,
      dns_zone = var.dns_zone,
      db_user = var.nextcloud_db_username,
      db_pass = var.nextcloud_db_password,
      replica_count = 1,
    })
  ]
}
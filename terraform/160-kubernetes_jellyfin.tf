#-------------------------------------------------------
# Jellyfin
#-------------------------------------------------------
resource "kubernetes_namespace_v1" "jellyfin" {
  metadata {
    name = "jellyfin"
    labels = {
      "pod-security.kubernetes.io/enforce" = "privileged"
      # "pod-security.kubernetes.io/enforce"         = "privileged"
      # "pod-security.kubernetes.io/enforce-version" = "latest"
      # "pod-security.kubernetes.io/audit"           = "privileged"
      # "pod-security.kubernetes.io/audit-version"   = "latest"
      # "pod-security.kubernetes.io/warn"            = "privileged"
      # "pod-security.kubernetes.io/warn-version"    = "latest"
    }
  }
}

#-------------------------------------------------------
# Jellyfin - Config Volume
#-------------------------------------------------------
resource "kubernetes_manifest" "jellyfin_config_longhorn_volume" {
  depends_on = [helm_release.longhorn]
  manifest = {
    apiVersion = "longhorn.io/v1beta2"
    kind       = "Volume"

    metadata = {
      name      = "jellyfin-config-volume-rwo"
      namespace = "longhorn-system"
    }

    spec = {
      size             = "10737418240" # 10Gi in bytes
      numberOfReplicas = 2
      frontend         = "blockdev"
      accessMode       = "rwo"
      dataLocality     = "disabled"
    }
  }
}

resource "kubernetes_persistent_volume_v1" "jellyfin_config" {
  depends_on = [kubernetes_manifest.jellyfin_config_longhorn_volume]
  metadata {
    name = "jellyfin-config"
  }

  spec {
    storage_class_name = "longhorn"
    access_modes       = ["ReadWriteOnce"]

    capacity = {
      storage = "10Gi"
    }

    persistent_volume_source {
      csi {
        driver        = "driver.longhorn.io"
        volume_handle = kubernetes_manifest.jellyfin_config_longhorn_volume.manifest.metadata.name
      }
    }
  }
  lifecycle {
    ignore_changes = [
      metadata
    ]
  }
}

resource "kubernetes_persistent_volume_claim_v1" "jellyfin_config" {
  depends_on = [kubernetes_persistent_volume_v1.jellyfin_config]
  metadata {
    name      = "jellyfin-config-pvc"
    namespace = kubernetes_namespace_v1.jellyfin.id
  }
  spec {
    volume_name = kubernetes_persistent_volume_v1.jellyfin_config.metadata.0.name
    # storage_class_name = "longhorn"
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "10Gi"
      }
    }
  }
}

#-------------------------------------------------------
# Jellyfin - Media Volume
#-------------------------------------------------------
resource "kubernetes_manifest" "jellyfin_media_longhorn_volume" {
  depends_on = [helm_release.longhorn]
  manifest = {
    apiVersion = "longhorn.io/v1beta2"
    kind       = "Volume"

    metadata = {
      name      = "jellyfin-media-volume-rwo"
      namespace = "longhorn-system"
    }

    spec = {
      size             = "1099511627776" # 10Gi in bytes
      numberOfReplicas = 1
      frontend         = "blockdev"
      accessMode       = "rwo"
      dataLocality     = "disabled"
    }
  }
}

resource "kubernetes_persistent_volume_v1" "jellyfin_media" {
  depends_on = [kubernetes_manifest.jellyfin_media_longhorn_volume]
  metadata {
    name = "jellyfin-media"
  }

  spec {
    storage_class_name = "longhorn"
    access_modes       = ["ReadWriteOnce"]

    capacity = {
      storage = "1024Gi"
    }

    persistent_volume_source {
      csi {
        driver        = "driver.longhorn.io"
        volume_handle = kubernetes_manifest.jellyfin_media_longhorn_volume.manifest.metadata.name
      }
    }
  }
  lifecycle {
    ignore_changes = [
      metadata
    ]
  }
}

resource "kubernetes_persistent_volume_claim_v1" "jellyfin_media" {
  metadata {
    name      = "jellyfin-media-pvc"
    namespace = kubernetes_namespace_v1.jellyfin.id
  }

  spec {
    volume_name  = kubernetes_persistent_volume_v1.jellyfin_media.metadata.0.name
    access_modes = ["ReadWriteOnce"]

    resources {
      requests = {
        storage = "1Ti"
      }
    }

  }
}

#-------------------------------------------------------
# Jellyfin - Helm & Config
#-------------------------------------------------------
resource "local_file" "jellyfin_values" {
  content = templatefile("${path.module}/helm/templates/jellyfin.tftpl", {
    config_pvc    = kubernetes_persistent_volume_claim_v1.jellyfin_config.metadata.0.name
    media_pvc     = kubernetes_persistent_volume_claim_v1.jellyfin_media.metadata.0.name
    replica_count = 1
  })
  filename = "${path.module}/helm/tmp/jellyfin.yml"
}

# https://github.com/jellyfin/jellyfin-helm/tree/master/charts/jellyfin
resource "helm_release" "jellyfin" {
  depends_on        = [kubernetes_persistent_volume_claim_v1.jellyfin_media, kubernetes_persistent_volume_claim_v1.jellyfin_config]
  name              = "jellyfin"
  namespace         = kubernetes_namespace_v1.jellyfin.id
  create_namespace  = false
  repository        = "https://jellyfin.github.io/jellyfin-helm"
  chart             = "jellyfin"
  version           = "3.2.0"
  dependency_update = true

  values = [
    local_file.jellyfin_values.content
  ]
}

# Jellyfin - HTTPRoute
resource "kubernetes_manifest" "jellyfin_http_route" {
  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "HTTPRoute"
    metadata = {
      name      = "jellyfin"
      namespace = kubernetes_namespace_v1.jellyfin.id

      annotations = {
        "gethomepage.dev/enabled" = "true"
        "gethomepage.dev/name" = "Media Library"
        "gethomepage.dev/description" = "Jellyfin"
        "gethomepage.dev/icon" = "jellyfin.png"
        "gethomepage.dev/group" = "Apps"
        "gethomepage.dev/href" = "https://media.${var.dns_zone}"
        "gethomepage.dev/pod-selector" = "app.kubernetes.io/name=jellyfin"
        "gethomepage.dev/siteMonitor" = "https://media.${var.dns_zone}"
      }
    }
    spec = {
      hostnames = [
        "media.${var.dns_zone}",
      ]
      parentRefs = [
        {
          name = "traefik-gateway"
          namespace = kubernetes_namespace_v1.traefik.id
        },
      ]
      rules = [
        {
          backendRefs = [
            {
              name      = "jellyfin"
              namespace = kubernetes_namespace_v1.jellyfin.id
              port      = 8096
            },
          ]
          matches = [
            {
              path = {
                type  = "PathPrefix"
                value = "/"
              }
            },
          ]
        },
      ]
    }
  }
}
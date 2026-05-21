#-------------------------------------------------------
# Kiwix
#-------------------------------------------------------
resource "kubernetes_namespace_v1" "kiwix" {
  metadata {
    name = "kiwix"
    labels = {
      # "pod-security.kubernetes.io/enforce" = "privileged" // Only required for NFS
    }
  }
}

locals {
  kiwix_version = "3.8.2"
  kiwix_instances = {
    catalog = {
      size = 25 // Gi
    },
    wikipedia = {
      size = 120 // Gi
    },
    stackoverflow = {
      size = 80 // Gi
    }
    gutenberg = {
      size = 220 // Gi
    }
  }
}

#-------------------------------------------------------
# Kiwix - Zim Volume
#-------------------------------------------------------
resource "kubernetes_manifest" "kiwix_longhorn_volume" {
  for_each   = { for i, v in local.kiwix_instances : i => v }
  depends_on = [helm_release.longhorn]
  manifest = {
    apiVersion = "longhorn.io/v1beta2"
    kind       = "Volume"

    metadata = {
      name      = "kiwix-${each.key}-volume"
      namespace = "longhorn-system"
    }

    spec = {
      size             = "${tostring(each.value.size * 1073741824)}" // size Gi in bytes
      numberOfReplicas = 1
      frontend         = "blockdev"
      accessMode       = "rwx"
      dataLocality     = "disabled"
    }
  }
}

resource "kubernetes_persistent_volume_v1" "kiwix" {
  for_each   = { for i, v in local.kiwix_instances : i => v }
  depends_on = [kubernetes_manifest.kiwix_longhorn_volume]
  metadata {
    name = "kiwix-${each.key}"
  }

  spec {
    storage_class_name = "longhorn"
    access_modes       = ["ReadWriteMany"]

    capacity = {
      storage = "${each.value.size}Gi"
    }

    persistent_volume_source {
      csi {
        driver        = "driver.longhorn.io"
        volume_handle = kubernetes_manifest.kiwix_longhorn_volume[each.key].manifest.metadata.name
      }
    }
  }
  lifecycle {
    ignore_changes = [
      metadata
    ]
  }
}

resource "kubernetes_persistent_volume_claim_v1" "kiwix" {
  for_each   = { for i, v in local.kiwix_instances : i => v }
  depends_on = [kubernetes_persistent_volume_v1.kiwix]
  metadata {
    name      = "kiwix-${each.key}-pvc"
    namespace = kubernetes_namespace_v1.kiwix.id
  }
  spec {
    volume_name  = kubernetes_persistent_volume_v1.kiwix[each.key].metadata.0.name
    access_modes = ["ReadWriteMany"]
    resources {
      requests = {
        storage = "${each.value.size}Gi"
      }
    }
  }
}

#-------------------------------------------------------
# Kiwix - Serve Deployment
#-------------------------------------------------------
resource "kubernetes_deployment_v1" "kiwix" {
  metadata {
    name      = "kiwix"
    namespace = kubernetes_namespace_v1.kiwix.id

    labels = {
      app  = "kiwix"
      role = "kiwix-library"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app  = "kiwix"
        role = "kiwix-library"
      }
    }

    template {
      metadata {
        labels = {
          app  = "kiwix"
          role = "kiwix-library"
        }
      }

      spec {
        container {
          name  = "kiwix"
          image = "ghcr.io/kiwix/kiwix-serve:${local.kiwix_version}"

          args = [
            "--address=all",
            "--library",
            "/data/catalog/library.xml",
            # "--skipInvalid",
            # "--nosearchbar",
            # "--nolibrarybutton",
            "--blockexternal",
            # "--verbose",
            # "--urlRootLocation="
            "--contentServer",
            "https://library.${var.dns_zone}"
          ]

          port {
            container_port = 8080
          }

          volume_mount {
            name       = "data"
            mount_path = "/data/catalog"
            read_only  = true
          }
          volume_mount {
            name       = "data-wikipedia"
            mount_path = "/data/wikipedia"
            read_only  = true
          }
          volume_mount {
            name       = "data-stackoverflow"
            mount_path = "/data/stackoverflow"
            read_only  = true
          }
          volume_mount {
            name       = "data-gutenberg"
            mount_path = "/data/ProjectGutenberg"
            read_only  = true
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "256Mi"
            }

            limits = {
              cpu    = "500m"
              memory = "512Mi"
            }
          }
        }

        volume {
          name = "data"
          persistent_volume_claim {
            claim_name = "kiwix-catalog-pvc"
          }
        }
        volume {
          name = "data-wikipedia"
          persistent_volume_claim {
            claim_name = "kiwix-wikipedia-pvc"
          }
        }
        volume {
          name = "data-stackoverflow"
          persistent_volume_claim {
            claim_name = "kiwix-stackoverflow-pvc"
          }
        }
        volume {
          name = "data-gutenberg"
          persistent_volume_claim {
            claim_name = "kiwix-gutenberg-pvc"
          }
        }
      }
    }
  }
}

#-------------------------------------------------------
# Kiwix - Serve Service
#-------------------------------------------------------
resource "kubernetes_service_v1" "kiwix" {
  metadata {
    name      = "kiwix"
    namespace = kubernetes_namespace_v1.kiwix.id
  }

  spec {
    selector = {
      app  = "kiwix"
      role = "kiwix-library"
    }

    port {
      port = 8080
    }
  }
}

#-------------------------------------------------------
# Kiwix - HTTP Route / Reference Grant
#-------------------------------------------------------
resource "kubernetes_manifest" "kiwix_http_route" {
  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "HTTPRoute"
    metadata = {
      name      = "kiwix"
      namespace = kubernetes_namespace_v1.traefik.id
    }
    spec = {
      hostnames = [
        "library.${var.dns_zone}",
      ]
      parentRefs = [
        {
          name = "traefik-gateway"
        },
      ]
      rules = [
        {
          backendRefs = [
            {
              name      = "kiwix"
              namespace = kubernetes_namespace_v1.kiwix.id
              port      = 8080
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

resource "kubernetes_manifest" "kiwix_referencegrant" {
  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1beta1"
    kind       = "ReferenceGrant"
    metadata = {
      name      = "kiwix"
      namespace = kubernetes_namespace_v1.kiwix.id
    }
    spec = {
      from = [
        {
          group     = "gateway.networking.k8s.io"
          kind      = "HTTPRoute"
          namespace = kubernetes_namespace_v1.traefik.id
        },
      ]
      to = [
        {
          group = ""
          kind  = "Service"
          name  = "kiwix"
        },
      ]
    }
  }
}
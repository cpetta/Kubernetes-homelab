# -------------------------------------------------------
# Kubernetes - Traefik PVC
# -------------------------------------------------------
# resource "kubernetes_manifest" "traefik_data_longhorn_volume" {
#   manifest = {
#     apiVersion = "longhorn.io/v1beta2"
#     kind       = "Volume"

#     metadata = {
#       name      = "traefik-data-volume"
#       namespace = "longhorn-system"
#     }

#     spec = {
#       size             = "1073741824" # 1Gi in bytes
#       numberOfReplicas = 3
#       frontend         = "blockdev"
#       accessMode       = "rwx" // "rwo"
#       dataLocality     = "disabled"
#     }
#   }
# }

# resource "kubernetes_persistent_volume_v1" "traefik_data" {
#   depends_on = [kubernetes_manifest.traefik_data_longhorn_volume]
#   metadata {
#     name = "traefik-data"
#   }

#   spec {
#     storage_class_name = "longhorn"
#     access_modes       = ["ReadWriteMany"] // ["ReadWriteOnce"]

#     capacity = {
#       storage = "1Gi"
#     }

#     persistent_volume_source {
#       csi {
#         driver        = "driver.longhorn.io"
#         volume_handle = kubernetes_manifest.traefik_data_longhorn_volume.manifest.metadata.name
#       }
#     }
#   }
#   lifecycle {
#     ignore_changes = [
#       metadata
#     ]
#   }
# }

# resource "kubernetes_persistent_volume_claim_v1" "traefik_data" {
#   depends_on = [kubernetes_persistent_volume_v1.traefik_data]
#   metadata {
#     name      = "traefik-data-pvc"
#     namespace = kubernetes_namespace_v1.traefik.id
#   }
#   spec {
#     volume_name = kubernetes_persistent_volume_v1.traefik_data.metadata.0.name
#     # storage_class_name = "longhorn"
#     access_modes = ["ReadWriteMany"] // ["ReadWriteOnce"]
#     resources {
#       requests = {
#         storage = "1Gi"
#       }
#     }
#   }
# }

#-------------------------------------------------------
# Kubernetes - Traefik
#-------------------------------------------------------
resource "kubernetes_namespace_v1" "traefik" {
  metadata {
    name = "traefik"
    labels = {
      "pod-security.kubernetes.io/enforce" = "privileged"
    }
  }
}

resource "tls_private_key" "traefik" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "traefik" {
  private_key_pem       = tls_private_key.traefik.private_key_pem
  validity_period_hours = 8760 # 365 days

  subject {
    common_name = "*.docker.localhost"
  }

  allowed_uses = [
    "any_extended",
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
}

resource "kubernetes_secret_v1" "traefik_tls_secret" {
  metadata {
    name      = "local-selfsigned-tls"
    namespace = kubernetes_namespace_v1.traefik.id
  }

  data = {
    "tls.crt" = tls_self_signed_cert.traefik.cert_pem
    "tls.key" = tls_private_key.traefik.private_key_pem
  }

  type = "kubernetes.io/tls"
}

resource "helm_release" "traefik" {
  # depends_on = [kubernetes_persistent_volume_claim_v1.traefik_data]
  name              = "traefik"
  namespace         = kubernetes_namespace_v1.traefik.id
  create_namespace  = false
  dependency_update = true
  repository        = "https://traefik.github.io/charts"
  chart             = "traefik"
  version           = "41.0.0"
  values = [
    templatefile("${path.module}/helm/templates/traefik.tftpl", {
      dns_zone             = var.dns_zone,
      admin_email          = var.admin_email,
      password             = var.traefik_password,
      cloudflare_api_email = var.cloudflare_api_email,
      cloudflare_token     = var.cloudflare_token,
    })
  ]
}
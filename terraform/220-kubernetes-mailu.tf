#-------------------------------------------------------
# mailu - Config
#-------------------------------------------------------
locals {
  mailu = {
    version = "2.7.1"
    storage = {
      # Already exists
      # storage = {
      #   volume_name = "mailu-storage"
      #   size = 100 // Gi  
      #   accessMode = "ReadWriteOnce"
      #   replicas = 3
      # }
      admin = {
        volume_name = "mailu-admin"
        size = 20 // Gi  
        replicas = 3
      }
      postfix = {
        volume_name = "mailu-postfix"
        size = 20 // Gi  
        replicas = 3
      }
      dovecot = {
        volume_name = "mailu-dovecot"
        size = 20 // Gi  
        replicas = 3
      }
      rspamd = {
        volume_name = "mailu-rspamd"
        size = 1 // Gi  
        replicas = 3
      }
      clamav = {
        volume_name = "mailu-clamav"
        size = 2 // Gi  
        replicas = 3
      }
      webmail = {
        volume_name = "mailu-webmail"
        size = 20 // Gi  
        replicas = 3
      }
    }
    subnet = "mail"
  }
}

resource "kubernetes_namespace_v1" "mailu" {
  metadata {
    name = "mailu"
    labels = {
    #   "pod-security.kubernetes.io/enforce"         = "privileged"
    }
  }
}

#-------------------------------------------------------
# mailu - secrets
#-------------------------------------------------------
resource "kubernetes_secret_v1" "mailu_db_info" {
  type = "Opaque"
  metadata {
    name      = "mailu-db"
    namespace = kubernetes_namespace_v1.mailu.id
  }
  data = {
    database = "mailu"
    username = "mailu"
    password = var.mailu_db_password
  }
}

resource "kubernetes_secret_v1" "mailu_db_roundcube" {
  type = "Opaque"
  metadata {
    name      = "mailu-db-roundcube"
    namespace = kubernetes_namespace_v1.mailu.id
  }
  data = {
    database = "mailu"
    username = "mailu"
    password = var.mailu_db_password
  }
}

resource "kubernetes_secret_v1" "mailu_admin" {
  type = "Opaque"
  metadata {
    name      = "mailu-admin"
    namespace = kubernetes_namespace_v1.mailu.id
  }
  data = {
    password = var.mailu_admin_password
  }
}

#-------------------------------------------------------
# Mailu - Certificate
#-------------------------------------------------------
resource "kubectl_manifest" "mailu_certificate" {
  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"

    metadata = {
      name      = "mailu-certificate-prod"
      namespace = kubernetes_namespace_v1.mailu.id
    }

    spec = {
      secretName = "mailu-certificate"
      dnsNames = [
        "mail.${var.dns_zone}",
        "imap.${var.dns_zone}",
        "smtp.${var.dns_zone}",
        "pop3.${var.dns_zone}",
      ]
      issuerRef = {
        name = "cloudflare"
        kind = "ClusterIssuer"
      }
    }
  })
}

resource "kubectl_manifest" "mailu_certificate_staging" {
  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"

    metadata = {
      name      = "mailu-certificates-staging"
      namespace = kubernetes_namespace_v1.mailu.id
    }

    spec = {
      secretName = "mailu-certificates"
      dnsNames = [
        "mail.${var.dns_zone}",
        "imap.${var.dns_zone}",
      ]
      issuerRef = {
        name = "cloudflare-staging"
        kind = "ClusterIssuer"
      }
    }
  })
}

#-------------------------------------------------------
# mailu - Storage Volume
#-------------------------------------------------------
resource "kubernetes_manifest" "mailu_storage_longhorn_volume" {
  depends_on = [helm_release.longhorn]
  manifest = {
    apiVersion = "longhorn.io/v1beta2"
    kind       = "Volume"

    metadata = {
      name      = "mailu-storage"
      namespace = "longhorn-system"
    }

    spec = {
      size             = "${tostring(100 * 1073741824)}" // size Gi in bytes
      numberOfReplicas = 3
      frontend         = "blockdev"
      accessMode       = "rwx"
      dataLocality     = "disabled"
    }
  }
}

resource "kubernetes_persistent_volume_v1" "mailu_storage" {
  depends_on = [kubernetes_manifest.mailu_storage_longhorn_volume]
  metadata {
    name = "mailu-storage"
  }

  spec {
    storage_class_name = "longhorn"
    access_modes       = ["ReadWriteMany"]

    capacity = {
      storage = "100Gi"
    }

    persistent_volume_source {
      csi {
        driver        = "driver.longhorn.io"
        volume_handle = "mailu-storage"
      }
    }
  }
  lifecycle {
    ignore_changes = [
      metadata
    ]
  }
}

resource "kubernetes_persistent_volume_claim_v1" "mailu_storage" {
  depends_on = [kubernetes_persistent_volume_v1.mailu_storage]
  metadata {
    name      = "mailu-storage-pvc"
    namespace = kubernetes_namespace_v1.mailu.id
  }
  spec {
    volume_name = "mailu-storage"
    access_modes = ["ReadWriteMany"]
    resources {
      requests = {
        storage = "100Gi"
      }
    }
  }
}

#-------------------------------------------------------
# mailu - Additional Volumes
#-------------------------------------------------------
resource "kubernetes_manifest" "mailu_longhorn_volume" {
  depends_on = [helm_release.longhorn]
  for_each   = { for i, v in local.mailu.storage : i => v }
  manifest = {
    apiVersion = "longhorn.io/v1beta2"
    kind       = "Volume"

    metadata = {
      name      = each.value.volume_name
      namespace = "longhorn-system"
    }

    spec = {
      size             = "${tostring(each.value.size * 1073741824)}" // size Gi in bytes
      numberOfReplicas = 3
      frontend         = "blockdev"
      accessMode       = "rwo"
      dataLocality     = "disabled"
    }
  }
}

resource "kubernetes_persistent_volume_v1" "mailu" {
  depends_on = [kubernetes_manifest.mailu_longhorn_volume]
  for_each   = { for i, v in local.mailu.storage : i => v }
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

resource "kubernetes_persistent_volume_claim_v1" "mailu" {
  depends_on = [kubernetes_persistent_volume_v1.mailu]
  for_each   = { for i, v in local.mailu.storage : i => v }
  metadata {
    name      = "mailu-${each.key}-pvc"
    namespace = kubernetes_namespace_v1.mailu.id
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
# mailu - Helm & Config
#-------------------------------------------------------
# https://code.mailu.org/mailu-helm/mailu-helm
resource "helm_release" "mailu" {
  depends_on        = [
    kubernetes_persistent_volume_claim_v1.mailu,
    kubernetes_persistent_volume_claim_v1.mailu_storage
  ]
  name              = "mailu"
  namespace         = kubernetes_namespace_v1.mailu.id
  create_namespace  = false
  repository        = "https://mailu.github.io/helm-charts/"
  chart             = "mailu"
  version           = local.mailu.version
  values = [
    templatefile("${path.module}/helm/templates/mailu.tftpl", {
      pvc_mailu = "mailu-storage-pvc"
      pvc_admin = "mailu-admin-pvc"
      pvc_postfix = "mailu-postfix-pvc"
      pvc_dovecot = "mailu-dovecot-pvc"
      pvc_rspamd = "mailu-rspamd-pvc"
      pvc_clamav = "mailu-clamav-pvc"
      pvc_webmail = "mailu-webmail-pvc"
      subnet = local.mailu.subnet,
      dns_zone = var.dns_zone,
      db_secret = "mailu-db",
      admin_password_secret = "mailu-admin",
      realip = var.k8_service_list.rp,
      # realip = "192.168.0.244",
    #   oauth_secret = var.mailu_oauth_secret,
    #   replica_count = 1,
    })
  ]
}

#-------------------------------------------------------
# mailu - DNS Records
#-------------------------------------------------------
resource "dns_a_record_set" "mailu_mail" {
  zone     = "${var.dns_zone}."
  name     = "mail"
  addresses = [
    var.k8_service_list.rp,
  ]
}

resource "dns_a_record_set" "mailu_smtp" {
  zone     = "${var.dns_zone}."
  name     = "smtp"
  addresses = [
    var.k8_service_list.rp,
  ]
}

resource "dns_a_record_set" "mailu_imap" {
  zone     = "${var.dns_zone}."
  name     = "imap"
  addresses = [
    var.k8_service_list.rp,
  ]
}

resource "dns_a_record_set" "mailu_pop3" {
  zone     = "${var.dns_zone}."
  name     = "pop3"
  addresses = [
    var.k8_service_list.rp,
  ]
}

resource "dns_mx_record_set" "mailu_smtp" {
  zone = "${var.dns_zone}."
  ttl  = 300

  mx {
    preference = 10
    exchange   = "smtp.${var.dns_zone}."
  }
}

# commented out due conflict with the A record
# resource "dns_ns_record_set" "mail" {
#   zone = "${var.dns_zone}."
#   name = "mail"
#   nameservers = [
#     "ns1.${var.dns_zone}.",
#     "ns2.${var.dns_zone}.",
#   ]
#   ttl = 300
# }

#-------------------------------------------------------
# mailu - Gateway
#-------------------------------------------------------
resource "kubernetes_manifest" "mailu_gateway" {
  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "Gateway"

    metadata = {
      name = "mailu-gateway"
      namespace = resource.kubernetes_namespace_v1.mailu.id
    }

    spec = {
      gatewayClassName = "traefik"

      listeners = [
        {
          name      = "websecure"
          protocol  = "TLS"
          port      = 443
          hostnames = [
            "mail.${var.dns_zone}",
            "autoconfig.${var.dns_zone}",
            "mta-sts.${var.dns_zone}",
          ]

          tls = {
            mode = "Passthrough"
          }
        },
        {
          name     = "submissions"
          protocol = "TLS"
          port     = 465

          tls = { # questioning
            mode = "Passthrough"
          }
        },
        {
          name     = "imaps"
          protocol = "TLS"
          port     = 993

          tls = {
            mode = "Passthrough"
          }
        },
        {
          name     = "pop3s"
          protocol = "TLS"
          port     = 995

          tls = {
            mode = "Passthrough"
          }
        },
        {
          name     = "sieve"
          protocol = "TCP"
          port     = 4190
        },
        {
          name     = "smtp"
          protocol = "TCP"
          port     = 25
        }
      ]
    }
  }
}

#-------------------------------------------------------
# mailu - TLS Routes
#-------------------------------------------------------
resource "kubernetes_manifest" "mailu_websecure_route" {
  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1alpha2"
    kind       = "TLSRoute"

    metadata = {
      name = "mailu-websecure"
      namespace = resource.kubernetes_namespace_v1.mailu.id
    }

    spec = {
      hostnames = [
        "mail.${var.dns_zone}",
        "autoconfig.${var.dns_zone}",
        "mta-sts.${var.dns_zone}"
      ]
      parentRefs = [
        {
          name        = kubernetes_manifest.mailu_gateway.manifest.metadata.name
          sectionName = "websecure"
        },
      ]
      rules = [
        {
          backendRefs = [
            {
              name = "mailu-front"
              port = 443
            }
          ]
        }
      ]
    }
  }
}

resource "kubernetes_manifest" "mailu_tlsroute_submissions" {
  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1alpha2"
    kind       = "TLSRoute"

    metadata = {
      name = "mailu-submissions"
      namespace = resource.kubernetes_namespace_v1.mailu.id
    }

    spec = {
      parentRefs = [
        {
          name        = kubernetes_manifest.mailu_gateway.manifest.metadata.name
          sectionName = "submissions"
        },
      ]

      hostnames = [
        "mail.${var.dns_zone}",
        "smtp.${var.dns_zone}",
      ]

      rules = [
        {
          backendRefs = [
            {
              name = "mailu-front"
              port = 465
            }
          ]
        }
      ]
    }
  }
}

resource "kubernetes_manifest" "mailu_tlsroute_imaps" {
  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1alpha2"
    kind       = "TLSRoute"

    metadata = {
      name = "mailu-imaps"
      namespace = resource.kubernetes_namespace_v1.mailu.id
    }

    spec = {
      parentRefs = [
        {
          name        = kubernetes_manifest.mailu_gateway.manifest.metadata.name
          sectionName = "imaps"
        },
      ]

      hostnames = [
        "mail.${var.dns_zone}",
        "imap.${var.dns_zone}",
      ]

      rules = [
        {
          backendRefs = [
            {
              name = "mailu-front"
              port = 993
            }
          ]
        }
      ]
    }
  }
}

resource "kubernetes_manifest" "mailu_tlsroute_pop3s" {
  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1alpha2"
    kind       = "TLSRoute"

    metadata = {
      name = "mailu-pop3s"
      namespace = resource.kubernetes_namespace_v1.mailu.id
    }

    spec = {
      parentRefs = [
        {
          name        = kubernetes_manifest.mailu_gateway.manifest.metadata.name
          sectionName = "pop3s"
        },
      ]

      hostnames = [
        "mail.${var.dns_zone}",
        "pop3.${var.dns_zone}",
      ]

      rules = [
        {
          backendRefs = [
            {
              name = "mailu-front"
              port = 993
            }
          ]
        }
      ]
    }
  }
}

resource "kubernetes_manifest" "mailu_tlsroute_sieve" {
  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1alpha2"
    kind       = "TLSRoute"

    metadata = {
      name = "mailu-sieve"
      namespace = resource.kubernetes_namespace_v1.mailu.id
    }

    spec = {
      parentRefs = [
        {
          name        = kubernetes_manifest.mailu_gateway.manifest.metadata.name
          sectionName = "sieve"
        },
      ]

      hostnames = [
        "mail.${var.dns_zone}",
      ]

      rules = [
        {
          backendRefs = [
            {
              name = "mailu-front"
              # port = 4190
              port = 14190
            }
          ]
        }
      ]
    }
  }
}

resource "kubernetes_manifest" "mailu_tlsroute_smtp" {
  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1alpha2"
    kind       = "TLSRoute"

    metadata = {
      name = "mailu-smtp"
      namespace = resource.kubernetes_namespace_v1.mailu.id
    }

    spec = {
      parentRefs = [
        {
          name        = kubernetes_manifest.mailu_gateway.manifest.metadata.name
          sectionName = "smtp"
        },
      ]

      hostnames = [
        "mail.${var.dns_zone}",
      ]

      rules = [
        {
          backendRefs = [
            {
              name = "mailu-front"
              port = 25
            }
          ]
        }
      ]
    }
  }
}
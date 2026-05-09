#-------------------------------------------------------
# Cert Manager - helm
#-------------------------------------------------------
resource "kubernetes_namespace_v1" "cert-manager" {
  metadata {
    name   = "cert-manager"
    labels = {}
  }
}

resource "helm_release" "cert_manager" {
  name       = "cert-manager"
  repository = "oci://quay.io/jetstack/charts"
  chart      = "cert-manager"
  namespace  = kubernetes_namespace_v1.cert-manager.id
  version    = "v1.20.2"

  set = [
    {
      name  = "crds.enabled"
      value = "true"
    },
    { # Disable during initial bootup
      name  = "extraArgs"
      value = "{--dns01-recursive-nameservers-only,--dns01-recursive-nameservers=1.1.1.1:53,1.0.0.1:53}"
    }
  ]
}

#-------------------------------------------------------
# Cert Manager - Cluster Issuer
#-------------------------------------------------------
resource "kubectl_manifest" "cert_manager_cluster_issuer_cloudflare_staging" {
  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = "cloudflare-staging"
    }
    spec = {
      acme = {
        email = var.admin_email
        privateKeySecretRef = {
          name = "cert-manager-private-key"
        }
        server = "https://acme-v02.api.letsencrypt.org/directory"
        solvers = [
          {
            dns01 = {
              cloudflare = {
                apiKeySecretRef = {
                  key  = "api-token"
                  name = "cloudflare-api-key-secret"
                }
                email = var.cloudflare_api_email
              }
            }
          },
        ]
      }
    }
  })
}

resource "kubectl_manifest" "cert_manager_cluster_issuer_cloudflare" {
  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = "cloudflare"
    }
    spec = {
      acme = {
        email = var.admin_email
        # preferredChain = "ISRG Root X1"
        privateKeySecretRef = {
          name = "cloudflare-private-key"
        }
        server = "https://acme-v02.api.letsencrypt.org/directory"
        solvers = [
          {
            dns01 = {
              cloudflare = {
                apiKeySecretRef = {
                  key  = var.cloudflare_token
                  name = "cloudflare-api-key-secret"
                }
                email = var.cloudflare_api_email
              }
            }
            # selector = {
            #   dnsZones = [
            #     "*.${var.dns_zone}",
            #     var.dns_zone,
            #   ]
            # }
          },
        ]
      }
    }
  })
}

#-------------------------------------------------------
# Cert Manager - Cloudflare provider
#-------------------------------------------------------
resource "kubernetes_secret_v1" "cloudflare_api_key" {
  depends_on = [helm_release.cert_manager]
  metadata {
    name      = "cloudflare-api-token-secret"
    namespace = kubernetes_namespace_v1.traefik.id
  }
  type = "Opaque"
  data = {
    api-token = var.cloudflare_token
  }
}

resource "kubernetes_manifest" "cloudflare_le_staging_cert_issuer" {
  depends_on = [kubernetes_secret_v1.cloudflare_api_key]
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "Issuer"
    metadata = {
      name      = "cloudflare-staging"
      namespace = kubernetes_namespace_v1.traefik.id
    }
    spec = {
      acme = {
        server = "https://acme-staging-v02.api.letsencrypt.org/directory" # staging
        email  = var.admin_email
        privateKeySecretRef = {
          name = "cloudflare-staging-key"
        }
        solvers = [
          {
            dns01 = {
              cloudflare = {
                apiTokenSecretRef = {
                  name = kubernetes_secret_v1.cloudflare_api_key.metadata.0.name
                  key  = "api-token"
                }
              }
              recursiveNameservers = [
                "1.1.1.1:53",
                "1.0.0.1:53",
              ]
              recursiveNameserversOnly = true
            }
          }
        ]
      }
    }
  }
}

resource "kubernetes_manifest" "cloudflare_le_prod_cert_issuer" {
  depends_on = [kubernetes_secret_v1.cloudflare_api_key]
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "Issuer"
    metadata = {
      name      = "cloudflare-prod"
      namespace = kubernetes_namespace_v1.traefik.id
    }
    spec = {
      acme = {
        server = "https://acme-v02.api.letsencrypt.org/directory"
        email  = var.admin_email
        privateKeySecretRef = {
          name = "cloudflare-prod-key"
        }
        solvers = [
          {
            dns01 = {
              cloudflare = {
                apiTokenSecretRef = {
                  name = kubernetes_secret_v1.cloudflare_api_key.metadata.0.name
                  key  = "api-token"
                }
              }
              recursiveNameservers = [
                "1.1.1.1:53",
                "1.0.0.1:53",
              ]
              recursiveNameserversOnly = true
            }
          }
        ]
      }
    }
  }
}

#-------------------------------------------------------
# Cert Manager - TLS Certificate
#-------------------------------------------------------
resource "kubectl_manifest" "wildcard_certificate" {
  # wait_for {
  #   field {
  #     key = "status.containerStatuses.[0].ready"
  #     value = "true"
  #   }
  #   field {
  #     key = "status.phase"
  #     value = "Running"
  #   }
  #   field {
  #     key = "status.podIP"
  #     value = "^(\\d+(\\.|$)){4}"
  #     value_type = "regex"
  #   }
  #   condition {
  #     type = "ContainersReady"
  #     status = "True"
  #   }
  #   condition {
  #     type = "Ready"
  #     status = "True"
  #   }
  # }
  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"

    metadata = {
      name      = "wildcard-cert"
      namespace = kubernetes_namespace_v1.traefik.id
    }

    spec = {
      secretName = "wildcard-cert"
      commonName = "*.${var.dns_zone}"
      dnsNames = [
        var.dns_zone,
        "*.${var.dns_zone}",
      ]
      issuerRef = {
        name = kubernetes_manifest.cloudflare_le_prod_cert_issuer.manifest.metadata.name
        kind = "Issuer"
      }
    }
  })
}
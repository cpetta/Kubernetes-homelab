resource "argocd_application" "cert-manager" {
  metadata {
    name      = "cert-manager"
    namespace = kubernetes_namespace_v1.argo.id
  }

  spec {
    source {
      repo_url = "quay.io/jetstack/charts"
      chart = "cert-manager"
      target_revision = "v1.20.2"
      
      helm {
        release_name = "cert-manager"
        parameter {
          name  = "crds.enabled"
          value = "true"
        }
        parameter {
          name  = "extraArgs"
          value = "{--dns01-recursive-nameservers-only,--dns01-recursive-nameservers=1.1.1.1:53,1.0.0.1:53}"
        }
      }
    }

    source {
      repo_url        = "git@git.${var.dns_zone}:chloe/homelab.git"
      target_revision = "HEAD"
      path            = "./applications/cert-manager"
      ref             = "config"
    }

    destination {
      server    = "https://kubernetes.default.svc"
      namespace = "cert-manager"
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
        server = "https://acme-staging-v02.api.letsencrypt.org/directory" # staging
        email = var.admin_email
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
        server = "https://acme-v02.api.letsencrypt.org/directory"
        email = var.admin_email
        # preferredChain = "ISRG Root X1"
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
  })
}

#-------------------------------------------------------
# Cert Manager - Cloudflare Secrets
#-------------------------------------------------------
resource "kubernetes_secret_v1" "cloudflare_api_key" {
  metadata {
    name      = "cloudflare-api-token-secret"
    namespace  = "cert-manager"
  }
  type = "Opaque"
  data = {
    api-token = var.cloudflare_token
  }
}

resource "kubernetes_secret_v1" "cloudflare_api_key_traefik" {
  metadata {
    name      = "cloudflare-api-token-secret"
    namespace = "traefik"
  }
  type = "Opaque"
  data = {
    api-token = var.cloudflare_token
  }
}

#-------------------------------------------------------
# Cert Manager - Cloudflare provider
#-------------------------------------------------------
resource "kubernetes_manifest" "cloudflare_le_staging_cert_issuer" {
  depends_on = [kubernetes_secret_v1.cloudflare_api_key]
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "Issuer"
    metadata = {
      name      = "cloudflare-staging"
      namespace = "traefik"
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
      namespace = "traefik"
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
resource "kubectl_manifest" "wildcard_certificate_staging" {
  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"

    metadata = {
      name      = "wildcard-cert-staging"
      namespace = "traefik"
    }

    spec = {
      secretName = "wildcard-cert-staging"
      commonName = "*.${var.dns_zone}"
      dnsNames = [
        var.dns_zone,
        "*.${var.dns_zone}",
      ]
      issuerRef = {
        name = kubernetes_manifest.cloudflare_le_staging_cert_issuer.manifest.metadata.name
        kind = "Issuer"
      }
    }
  })
}

resource "kubectl_manifest" "wildcard_certificate" {
  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"

    metadata = {
      name      = "wildcard-cert"
      namespace = "traefik"
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
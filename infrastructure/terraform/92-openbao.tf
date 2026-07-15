#-------------------------------------------------------
# OpenBao - Dns
#-------------------------------------------------------
resource "dns_a_record_set" "openbao" {
  zone     = "${var.dns_zone}."
  name     = "vault"
  addresses = [
    var.k8_service_list.rp,
  ]
}

#-------------------------------------------------------
# OpenBao - Certificate
#-------------------------------------------------------
# resource "local_file" "cert" {
#   content = yamlencode({
#     apiVersion = "cert-manager.io/v1"
#     kind       = "Certificate"

#     metadata = {
#       name      = "vault-certificate-prod"
#       namespace = "vault"
#     }

#     spec = {
#       secretName = "vault-certificate"
#       dnsNames = [
#         "vault.${var.dns_zone}",
#       ]
#       issuerRef = {
#         name = "cloudflare"
#         kind = "ClusterIssuer"
#       }
#     }
#   })
#   filename = "${path.module}/../../applications/openbao/vault-tls-certificate.yaml"
# }

resource "kubectl_manifest" "openbao_certificate" {
  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"

    metadata = {
      name      = "vault-certificate-prod"
      namespace = "vault"
    }

    spec = {
      secretName = "vault-certificate"
      dnsNames = [
        "vault.${var.dns_zone}",
      ]
      issuerRef = {
        name = "cloudflare"
        kind = "ClusterIssuer"
      }
    }
  })
}

#-------------------------------------------------------
# OpenBao - Gateway
#-------------------------------------------------------
resource "kubernetes_manifest" "openbao_gateway" {
  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "Gateway"

    metadata = {
      name = "vault-gateway"
      namespace = "vault"
    }

    spec = {
      gatewayClassName = "traefik"

      listeners = [
        {
          name      = "websecure"
          protocol  = "TLS"
          port      = 443
          hostnames = ["vault.${var.dns_zone}"]

          tls = {
            mode = "Passthrough"
          }
        },
      ]
    }
  }
}

resource "argocd_application" "openbao" {
  metadata {
    name      = "openbao"
    namespace = kubernetes_namespace_v1.argo.id
  }

  spec {
    source {
      repo_url = "https://openbao.github.io/openbao-helm"
      chart = "openbao"
      target_revision = "0.28.4"
      
      helm {
        release_name = "openbao"
        # value_files = ["$values/vault/values.yaml"]
        values = templatefile("${path.module}/helm/templates/openbao.tftpl", {
          subnet         = "vault",
          dns_zone       = var.dns_zone,
        }) 
      }
    }

    # source {
    #   repo_url        = "git@git.${var.dns_zone}:chloe/homelab.git"
    #   target_revision = "HEAD"
    #   path            = "./applications/vault/values.yaml"
    #   ref             = "values"
    # }

    destination {
      server    = "https://kubernetes.default.svc"
      namespace = "vault"
    }

    sync_policy {
      # automated {
      #   prune       = true
      #   self_heal   = true
      #   allow_empty = true
      # }
      sync_options = [
        "CreateNamespace=true",
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
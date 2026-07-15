resource "argocd_application" "external-secrets" {
  metadata {
    name      = "external-secrets"
    namespace = kubernetes_namespace_v1.argo.id
  }

  spec {
    source {
      repo_url = "https://charts.external-secrets.io"
      chart = "external-secrets"
      target_revision = "2.7.0"
      
      helm {
        release_name = "external-secrets"
        parameter {
          name  = "installCRDs"
          value = "true"
        }
      }
    }

    source {
      repo_url        = "git@git.${var.dns_zone}:chloe/homelab.git"
      target_revision = "HEAD"
      path            = "./applications/external-secrets"
      ref             = "config"
    }

    destination {
      server    = "https://kubernetes.default.svc"
      namespace = "external-secrets"
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

    ignore_difference {
      group         = "apps"
      kind          = "Deployment"
      json_pointers = ["/spec/replicas"]
    }
  }
}

locals {
  external_secrets = {
    token_list = [
      "cert-manager",
    ]
  }
}

resource "vault_policy" "external-secrets" {
  for_each = { for i, v in local.external_secrets.token_list : v => v}
  name = each.value
  policy = <<EOT

path "${each.value}/data/*" {
  capabilities = ["read", "list"]
}
path "auth/token/lookup-self" {
    capabilities = ["read", "list"]
}
path "auth/token/renew-self" {
    capabilities = ["update"]
}
path "auth/token/revoke-self" {
    capabilities = ["update"]
}
  EOT
}
resource "vault_token" "this" {
  for_each = { for i, v in local.external_secrets.token_list : v => v}
  policies = [each.value]
  renewable = true
  ttl = "24h"

  renew_min_lease = 43200
  renew_increment = 86400

  metadata = {
    "namespace" = each.value
  }
}

# ephemeral "vault_token" "this" {
#   for_each = { for i, v in local.external_secrets.token_list : v => v}
#   policies = [each.value]
#   ttl      = "1h"
# }

resource "kubernetes_secret_v1" "external-secrets-tokens" {
  for_each = { for i, v in local.external_secrets.token_list : v => v}
  metadata {
    name      = "${each.value}-vault-token"
    namespace = each.value
  }
  
  type = "Opaque"
  data_wo_revision = 1
  data_wo = {
    token = vault_token.this[each.key].client_token
  }
}

resource "kubernetes_manifest" "external-secrets-secret-store" {
  depends_on = [kubernetes_secret_v1.external-secrets-tokens]
  for_each = { for i, v in local.external_secrets.token_list : v => v}
  manifest = {
    apiVersion = "external-secrets.io/v1"
    kind       = "SecretStore"

    metadata = {
      name      = each.value
      namespace = each.value
    }
    
    spec = {
      provider = {
        vault = {
          server: "http://vault.${var.dns_zone}"
          path = each.value
          version = "v2"
          auth = {
            tokenSecretRef = {
              name = "${each.value}-vault-token"
              namespace = each.value
              key = "token"
            }
          }
        }
      }
    }
  }
}

resource "vault_mount" "this" {
  for_each = { for i, v in local.external_secrets.token_list : v => v}
  path        = each.value
  type        = "kv"
  options     = { version = "2" }
}
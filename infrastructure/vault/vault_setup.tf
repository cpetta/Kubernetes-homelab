terraform {
  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "5.10.1"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "3.0.1"
    }
  }
}

#-------------------------------------------------------
# Variables
#-------------------------------------------------------
variable "vault_token" {}
variable "vault_password_chloe" {}

variable "admin_email" {}
variable "local_admin_email" {}
variable "dns_zone" {}
variable "dns_tsig_secret" {}
variable "ssh_public_key" {}
variable "pm_api_token" {}
variable "pm_api_url" {}
variable "pm_api_url_remote" {}

variable "argocd_oidc_secret" {}
variable "argocd_admin_password" {}

variable "tailscale_auth_key" {}

variable "pm_pasword" {}
variable "cipassword" {}
variable "cipassword_hash" {}
variable "traefik_password" {}
variable "longhorn_password" {}
variable "grafana_password" {}
variable "postgress_password" {}
variable "redis_password" {}
variable "keycloak_db_password" {}
variable "keycloak_admin_password" {}

variable "backblaze_application_key_ID" {}
variable "backblaze_application_key_key" {}

variable "forgejo_db_username" {}
variable "forgejo_db_password" {}
variable "forgejo_oauth_secret" {}
variable "forgejo_ssh_fingerprint" {}

variable "nextcloud_db_username" {}
variable "nextcloud_db_password" {}

variable "mailu_db_password" {}
variable "mailu_admin_password" {}

variable "harbor_admin_password" {}
variable "harbor_db_password" {}
variable "harbor_talos_robot_password" {}
variable "harbor_terraform_robot_password" {}
variable "harbor_oidc_client_secret" {}

variable "cloudflare_api_email" {}
variable "cloudflare_token" {}

variable "oauth_services" {}

variable "grafana_client_id" {}
variable "grafana_client_secret" {}

variable "gateway_ip" {}

variable "pm_node_list" {}
variable "dns_server_list" {}
variable "reverse_proxy_list" {}
variable "k8_control_plain_list" {}
variable "k8_control_plain_ha_ip" {}
variable "k8_storage_node_list" {}
variable "k8_metal_control_list" {}
variable "k8_metal_worker_list" {}
variable "k8_service_list" {}

variable "k8_dns_server_list" {}
variable "dns_password" {}
variable "dns_cert_password" {}

variable "etcdCA_crt" {}
variable "etcd_crt" {}
variable "etcd_key" {}

#-------------------------------------------------------
# Login with root token using bao login, create user
#-------------------------------------------------------
provider "kubernetes" {
  config_path = "../terraform/kubeconfig"
}

provider "vault" {
  address = "https://vault.${var.dns_zone}"
}

#-------------------------------------------------------
# Setup userpass auth type
#-------------------------------------------------------
resource "vault_auth_backend" "userpass" {
  type = "userpass"
  path = "userpass"
}

#-------------------------------------------------------
# Create homelab secrets store
#-------------------------------------------------------
resource "vault_mount" "homelab_core" {
  path        = "homelab-core"
  type        = "kv"
  options     = { version = "2" }
  description = "General KV Store mount"
}

#-------------------------------------------------------
# Setup Policies
#-------------------------------------------------------
resource "vault_policy" "admin" {
  name = "admin"
  policy = <<EOT
path "homelab-core/*" {
  capabilities = ["create", "read", "update", "patch", "delete", "list"]
}
EOT
}

#-------------------------------------------------------
# Setup Accounts
#-------------------------------------------------------
resource "vault_userpass_auth_backend_user" "chloe" {
  mount                = vault_auth_backend.userpass.path
  username             = "chloe"
  password_wo          = var.vault_password_chloe
  password_wo_version  = 1

  token_policies = ["admin"]
  token_ttl      = 3600
  token_max_ttl  = 7200
}

#-------------------------------------------------------
# Kubernetes Auth Type
#-------------------------------------------------------
# locals {
#   kubeconfig = yamldecode(local_file.kubeconfig.content)
#   kubernetes_ca_cert = local.kubeconfig.clusters[0].cluster.certificate-authority-data
# }

# resource "vault_auth_backend" "kubernetes" {
#   type = "kubernetes"
# }

# resource "vault_kubernetes_auth_backend_config" "this" {
#   backend = vault_auth_backend.kubernetes.path
#   kubernetes_host = var.k8_control_plain_ha_ip
#   kubernetes_ca_cert = local.kubernetes_ca_cert
# }

# resource "vault_kubernetes_auth_backend_role" "external_secrets" {
#   backend = vault_auth_backend.kubernetes.path
#   role_name = "external-secrets"
#   bound_service_account_names = ["external-secrets"]
#   bound_service_account_namespaces = ["external-secrets"]
#   token_policies = ["external-secrets"]
#   token_ttl     = 3600
#   token_max_ttl = 7200
# }


locals {
  external_secrets = {
    secret_list = [
      "cert-manager",
      "harbor",
      "metrics",
      "keycloak"
    ]
  }
}

resource "vault_policy" "this" {
  for_each = { for i, v in local.external_secrets.secret_list : v => v}
  name = each.value
  policy = <<EOT

path "${each.value}/*" {
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

# resource "vault_token" "this" {
#   for_each = { for i, v in local.external_secrets.secret_list : v => v}
#   policies = [each.value]
#   renewable = true
#   ttl = "24h"

#   renew_min_lease = 43200
#   renew_increment = 86400

#   metadata = {
#     "namespace" = each.value
#   }
# }

# resource "kubernetes_manifest" "external-secrets-secret-store" {
#   depends_on = [kubernetes_secret_v1.external-secrets-password]
#   for_each = { for i, v in local.external_secrets.secret_list : v => v}
#   manifest = {
#     apiVersion = "external-secrets.io/v1"
#     kind       = "SecretStore"

#     metadata = {
#       name      = each.value
#       namespace = each.value
#     }
    
#     spec = {
#       provider = {
#         vault = {
#           server: "http://vault.${var.dns_zone}"
#           path = each.value
#           version = "v2"
#           auth = {
#             tokenSecretRef = {
#               name = "${each.value}-vault-token"
#               namespace = each.value
#               key = "token"
#             }
#           }
#         }
#       }
#     }
#   }
# }

resource "vault_mount" "this" {
  for_each = { for i, v in local.external_secrets.secret_list : v => v}
  path        = each.value
  type        = "kv"
  options     = { version = "2" }
}

resource "random_password" "password" {
  for_each = { for i, v in local.external_secrets.secret_list : v => v}
  length           = 30
}

resource "vault_userpass_auth_backend_user" "external-secrets" {
  for_each = { for i, v in local.external_secrets.secret_list : v => v}
  depends_on = [ vault_policy.this ]
  mount                = "userpass"
  username             = each.key
  password_wo          = random_password.password[each.key].result
  password_wo_version  = 2
  token_policies = [each.value]
  token_ttl      = 3600
  token_max_ttl  = 7200
}

resource "kubernetes_secret_v1" "external-secrets-password" {
  for_each = { for i, v in local.external_secrets.secret_list : v => v}
  metadata {
    name      = "${each.value}-vault-user-password"
    namespace = each.value
  }
  
  type = "Opaque"
  data_wo_revision = 2
  data_wo = {
    password = random_password.password[each.key].result
  }
}





#-------------------------------------------------------
# Cloudflare Secrets
#-------------------------------------------------------
resource "vault_kv_secret_v2" "cloudflare" {
  mount               = vault_mount.this["cert-manager"].path
  name                = "cloudflare"
  cas                 = 1
  delete_all_versions = true
  data_json = jsonencode(
    {
      api-token = var.cloudflare_token
    }
  )
}

#-------------------------------------------------------
# Harbor Secrets
#-------------------------------------------------------
resource "vault_kv_secret_v2" "harbor-admin-password" {
  mount               = vault_mount.this["harbor"].path
  name                = "harbor-admin-password"
  cas                 = 1
  delete_all_versions = true
  data_json = jsonencode(
    {
      password = var.harbor_admin_password
    }
  )
}

resource "vault_kv_secret_v2" "harbor-db-password" {
  mount               = vault_mount.this["harbor"].path
  name                = "harbor-db-password"
  cas                 = 1
  delete_all_versions = true
  data_json = jsonencode(
    {
      password = var.harbor_db_password
    }
  )
}

#-------------------------------------------------------
# Metrics Secrets
#-------------------------------------------------------
resource "vault_kv_secret_v2" "grafana-admin-auth" {
  mount               = vault_mount.this["metrics"].path
  name                = "grafana-admin-auth"
  cas                 = 1
  delete_all_versions = true
  data_json = jsonencode(
    {
      username = "admin"
      password = var.grafana_password
    }
  )
}

resource "vault_kv_secret_v2" "etcd-client-cert" {
  mount               = vault_mount.this["metrics"].path
  name                = "etcd-client-cert"
  cas                 = 1
  delete_all_versions = true
  data_json = jsonencode(
    {
      etcd-ca         = var.etcdCA_crt
      etcd-client     = var.etcd_crt
      etcd-client-key = var.etcd_key
    }
  )
}

#-------------------------------------------------------
# Keycloak Secrets
#-------------------------------------------------------
resource "vault_kv_secret_v2" "keycloak-secrets" {
  mount               = vault_mount.this["keycloak"].path
  name                = "keycloak-config"
  cas                 = 1
  delete_all_versions = true
  data_json = jsonencode(
    {
      db-user = "keycloak_default"
      db-password = var.keycloak_db_password
      keycloak-password = var.keycloak_admin_password
    }
  )
}
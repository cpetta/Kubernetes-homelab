terraform {
  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "5.10.1"
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
# Cloudflare Secrets
#-------------------------------------------------------
resource "vault_kv_secret_v2" "cloudflare" {
  mount               = "cert-manager"
  name                = "cloudflare"
  cas                 = 1
  delete_all_versions = true
  data_json = jsonencode(
    {
      api-token = var.cloudflare_token
    }
  )
}
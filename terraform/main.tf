terraform {
  required_providers {
    dns = {
      source  = "hashicorp/dns"
      version = " ~> 3.5.0"
    }
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.97.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "2.4.0"
    }
    talos = {
      source  = "siderolabs/talos"
      version = "0.11.0-beta.1"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "3.0.1"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "3.1.1"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "4.2.1"
    }
    htpasswd = {
      source  = "loafoe/htpasswd"
      version = "2.1.0"
    }
    kubectl = {
      source = "alekc/kubectl"
    }
  }
}

#-------------------------------------------------------
# Variables
#-------------------------------------------------------
variable "local" {
  type    = bool
  default = true
}

variable "admin_email" {}
variable "dns_zone" {}
variable "dns_tsig_secret" {}
variable "ssh_public_key" {}
variable "pm_api_token" {}
variable "pm_api_url" {}
variable "pm_api_url_remote" {}

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

variable "nextcloud_db_username" {}
variable "nextcloud_db_password" {}

variable "harbor_admin_password" {}
variable "harbor_db_password" {}
variable "harbor_talos_robot_password" {}

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

locals {
  k8_cluster_config = {
    kubernetes_version = "1.36.1"
    name               = "Chloes_Cluster"
    endpoint           = "https://${var.k8_control_plain_ha_ip}:6443"
  }
}

#-------------------------------------------------------
# Providers
#-------------------------------------------------------
provider "proxmox" {
  endpoint  = var.local ? var.pm_api_url : var.pm_api_url_remote
  api_token = var.pm_api_token
  username  = "root@pam"
  password  = var.pm_pasword
  insecure  = true

  ssh {
    username    = "root"
    password    = var.pm_pasword
    private_key = file("../ssh/private_key")
    agent       = true

    node {
      name    = var.pm_node_list[0].name
      address = var.local ? var.pm_node_list[0].ip_address : var.pm_node_list[0].name
    }
    node {
      name    = var.pm_node_list[1].name
      address = var.local ? var.pm_node_list[1].ip_address : var.pm_node_list[1].name
    }
    # node {
    #   name    = var.pm_node_list[2].name
    #   address = var.local ? var.pm_node_list[2].ip_address : var.pm_node_list[2].name
    # }
  }
}

provider "kubernetes" {
  config_path = local_file.kubeconfig.filename
}

provider "helm" {
  kubernetes = {
    config_path = local_file.kubeconfig.filename
  }
}

provider "kubectl" {
  config_path = local_file.kubeconfig.filename
}

provider "talos" {}
provider "tls" {}
provider "htpasswd" {}

#-------------------------------------------------------
# Talos Secrets Resource
#-------------------------------------------------------
resource "talos_machine_secrets" "this" {}

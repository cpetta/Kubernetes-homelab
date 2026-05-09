#-------------------------------------------------------
# Talos Control Plain Nodes
#-------------------------------------------------------
data "talos_machine_configuration" "controlplane" {
  cluster_name       = local.k8_cluster_config.name
  machine_type       = "controlplane"
  cluster_endpoint   = local.k8_cluster_config.endpoint
  machine_secrets    = talos_machine_secrets.this.machine_secrets
  kubernetes_version = local.k8_cluster_config.kubernetes_version
}

data "talos_client_configuration" "controlplane" {
  cluster_name         = local.k8_cluster_config.name
  client_configuration = talos_machine_secrets.this.client_configuration
  endpoints            = [for v in var.k8_control_plain_list : v.ip_address]
}

resource "talos_machine_configuration_apply" "controlplane" {
  for_each                    = { for i, v in var.k8_control_plain_list : i => v }
  depends_on                  = [proxmox_virtual_environment_vm.k8cp]
  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.controlplane.machine_configuration
  node                        = each.value.ip_address
  config_patches              = [yamlencode(local.talos_control_plane_patch)]
}

resource "local_file" "talosconfig" {
  content  = data.talos_client_configuration.controlplane.talos_config
  filename = "${path.module}/../talosconfig"
}

resource "talos_cluster_kubeconfig" "controlplane" {
  for_each             = { for i, v in var.k8_control_plain_list : i => v }
  node                 = each.value.ip_address
  client_configuration = talos_machine_secrets.this.client_configuration
}

resource "local_file" "kubeconfig" {
  content  = talos_cluster_kubeconfig.controlplane[0].kubeconfig_raw
  filename = "${path.module}/../kubeconfig"
}

#-------------------------------------------------------
# Backups
#-------------------------------------------------------
resource "local_file" "controlplane_client_config_backup" {
  for_each = { for i, v in var.k8_control_plain_list : i => v if i > 0 }
  content  = yamlencode(talos_machine_secrets.this.client_configuration)
  filename = "${path.module}/../backups/talos/controlplane_client_config_${each.value.name}.yaml"
}

resource "local_file" "controlplane_machine_config_backup" {
  for_each = { for i, v in var.k8_control_plain_list : i => v if i > 0 }
  content  = data.talos_machine_configuration.controlplane.machine_configuration
  filename = "${path.module}/../backups/talos/controlplane_machine_config_${each.value.name}.yaml"
}

resource "local_file" "talosconfig_bakcup" {
  content  = data.talos_client_configuration.controlplane.talos_config
  filename = "${path.module}/../backups/talosconfig"
}

resource "local_file" "secrets_backup" {
  content  = jsonencode(talos_machine_secrets.this)
  filename = "${path.module}/../backups/secrets.json"
}
#-------------------------------------------------------
# Talos Worker Nodes
#-------------------------------------------------------
data "talos_machine_configuration" "storage" {
  cluster_name       = local.k8_cluster_config.name
  machine_type       = "worker"
  cluster_endpoint   = local.k8_cluster_config.endpoint
  machine_secrets    = talos_machine_secrets.this.machine_secrets
  kubernetes_version = local.k8_cluster_config.kubernetes_version
}

data "talos_client_configuration" "storage" {
  cluster_name         = local.k8_cluster_config.name
  client_configuration = talos_machine_secrets.this.client_configuration
  endpoints            = [var.k8_storage_node_list[0].ip_address]
}

resource "talos_machine_configuration_apply" "storage" {
  for_each                    = { for i, v in var.k8_storage_node_list : i => v }
  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.storage.machine_configuration
  node                        = each.value.ip_address
  config_patches              = [yamlencode(local.talos_storage_patch)]

  lifecycle {
    replace_triggered_by = [
      proxmox_virtual_environment_vm.k8s[each.key]
    ]
  }
}

#-------------------------------------------------------
# Backups
#-------------------------------------------------------
resource "local_file" "worker_client_config_backup" {
  for_each = { for i, v in var.k8_storage_node_list : i => v if i > 0 }
  content  = yamlencode(talos_machine_secrets.this.client_configuration)
  filename = "${path.module}/../backups/talos/worker_client_config_${each.value.name}.yaml"
}

resource "local_file" "worker_machine_config_backup" {
  for_each = { for i, v in var.k8_storage_node_list : i => v if i > 0 }
  content  = data.talos_machine_configuration.controlplane.machine_configuration
  filename = "${path.module}/../backups/talos/worker_machine_config_${each.value.name}.yaml"
}
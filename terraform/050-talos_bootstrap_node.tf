#-------------------------------------------------------
# Talos Control Plain Bootstrap
#-------------------------------------------------------
# data "talos_client_configuration" "k8_bootstrap_node" {
#   cluster_name         = local.k8_cluster_config.name
#   client_configuration = talos_machine_secrets.this.client_configuration
#   endpoints            = [var.k8_control_plain_list[0].ip_address]
# }

# data "talos_machine_configuration" "k8_bootstrap_node" {
#   depends_on         = [proxmox_virtual_environment_vm.k8cp]
#   cluster_name       = local.k8_cluster_config.name
#   machine_type       = "controlplane"
#   cluster_endpoint   = local.k8_cluster_config.endpoint
#   machine_secrets    = talos_machine_secrets.this.machine_secrets
#   kubernetes_version = local.k8_cluster_config.kubernetes_version
# }

# resource "talos_machine_configuration_apply" "k8_bootstrap_node" {
#   depends_on                  = [proxmox_virtual_environment_vm.k8cp[0]]
#   node                        = var.k8_control_plain_list[0].ip_address
#   client_configuration        = talos_machine_secrets.this.client_configuration
#   machine_configuration_input = data.talos_machine_configuration.k8_bootstrap_node.machine_configuration
#   config_patches              = [yamlencode(local.talos_control_plane_patch)]
# }

# resource "talos_machine_bootstrap" "k8_bootstrap_node" {
#   # depends_on           = [talos_machine_configuration_apply.k8_bootstrap_node]
#   node                 = var.k8_control_plain_list[0].ip_address
#   client_configuration = talos_machine_secrets.this.client_configuration
# }

# resource "talos_cluster_kubeconfig" "k8_bootstrap_node" {
#   # depends_on           = [talos_machine_bootstrap.k8_bootstrap_node]
#   node                 = var.k8_control_plain_list[0].ip_address
#   client_configuration = talos_machine_secrets.this.client_configuration
# }
#-------------------------------------------------------
# Talos Control Plain Nodes
#-------------------------------------------------------
resource "local_file" "k8cp_snippet" {
  for_each = { for i, v in var.k8_control_plain_list : i => v }
  content = templatefile("${path.module}/cloud-init/templates/talos.tftpl", {
    hostname    = each.value.name
    mac_address = ""
  })
  filename = "${path.module}/cloud-init/tmp/cloud_config_${each.value.name}.yml"
}

resource "proxmox_virtual_environment_file" "k8cp_cloud_config" {
  for_each     = { for i, v in var.k8_control_plain_list : i => v }
  depends_on   = [resource.local_file.k8cp_snippet]
  content_type = "snippets"
  datastore_id = "local"
  node_name    = each.value.host_node
  source_file {
    path = resource.local_file.k8cp_snippet[each.key].filename
  }
}

#-------------------------------------------------------
# Talos Storage Nodes
#-------------------------------------------------------
# resource "local_file" "k8w_snippet_storage" {
#   for_each = { for i, v in var.k8_storage_node_list : i => v }
#   content = templatefile("${path.module}/cloud-init/templates/talos.tftpl", {
#     hostname    = each.value.name
#     mac_address = ""
#   })
#   filename = "${path.module}/cloud-init/tmp/cloud_config_k8w${each.key}.yml"
# }

# resource "proxmox_virtual_environment_file" "k8w_cloud_config_storage" {
#   for_each     = { for i, v in var.k8_storage_node_list : i => v }
#   depends_on   = [resource.local_file.k8w_snippet_storage]
#   content_type = "snippets"
#   datastore_id = "local"
#   node_name    = each.value.host_node
#   source_file {
#     path = local_file.k8w_snippet_storage[each.key].filename
#   }
# }
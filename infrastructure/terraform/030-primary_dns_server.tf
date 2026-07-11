#-------------------------------------------------------
# DNS - bootstrap/backup (disabled via var.dns_server_list)
#-------------------------------------------------------
resource "local_file" "dns_snippet" {
  for_each = { for i, v in var.dns_server_list : i => v }
  content = templatefile("${path.module}/cloud-init/templates/common.tftpl", {
    hostname           = "dns${each.value.id}"
    tailscale_auth_key = var.tailscale_auth_key
    cipassword_hash    = var.cipassword_hash
    ssh_public_key     = var.ssh_public_key
  })
  filename = "${path.module}/cloud-init/tmp/cloud_config_dns${each.value.id}.yml"
}

resource "proxmox_virtual_environment_file" "dns_cloud_config" {
  for_each     = { for i, v in var.dns_server_list : i => v }
  depends_on   = [resource.local_file.dns_snippet]
  content_type = "snippets"
  datastore_id = "local"
  node_name    = each.value.host_node
  source_file {
    path = resource.local_file.dns_snippet[each.key].filename
  }
}

resource "proxmox_virtual_environment_vm" "dns" {
  for_each = { for i, v in var.dns_server_list : i => v }
  # vm_id       = 101
  name                = "dns${each.value.id}"
  node_name           = each.value.host_node
  description         = "Managed by Terraform"
  tags                = ["terraform", "ubuntu"]
  started             = true
  on_boot             = true
  reboot_after_update = true

  cpu {
    cores = 1
    type  = "host"
  }
  memory {
    dedicated = 2048
    floating  = 2048 # set equal to dedicated to enable ballooning
  }
  disk {
    datastore_id = "local-lvm"
    import_from  = proxmox_virtual_environment_download_file.ubuntu_cloud_image[each.value.host_node].id
    interface    = "scsi0"
    discard      = "on"
    size         = 10
  }

  initialization {
    datastore_id      = "local-lvm"
    user_data_file_id = proxmox_virtual_environment_file.dns_cloud_config[each.key].id

    ip_config {
      ipv4 {
        address = "${each.value.ip_address}/24"
        gateway = var.gateway_ip
      }
    }
    dns {
      servers = ["9.9.9.9", "1.1.1.1", "1.0.0.1"]
    }
  }

  network_device {
    bridge = "vmbr0"
    model  = "virtio"
  }

  agent {
    enabled = true
  }

  startup {
    down_delay = -1
    order      = -1
    up_delay   = -1
  }

  lifecycle {
    ignore_changes = [
      startup,
      started,
      initialization,
    ]
  }
}
#-------------------------------------------------------
# Talos Update Check
#-------------------------------------------------------
locals {
  talos_version_latest = element(data.talos_image_factory_versions.this.talos_versions, length(data.talos_image_factory_versions.this.talos_versions) - 1)
}

output "talos_check_version" {
  value = var.k8_metal_worker_list["k8mw1"].talos_version != local.talos_version_latest ? "Talos update available: ${var.k8_metal_worker_list["k8mw1"].talos_version} -> ${local.talos_version_latest}" : "Talos is up-to-date"
}

#-------------------------------------------------------
# Talos Update Proxmox Control Planes
#-------------------------------------------------------
data "talos_image_factory_extensions_versions" "latest_qemu_controlplane" {
  talos_version = local.talos_version_latest
  filters = local.talos_qemu_control_plane_image_filters
}

resource "talos_image_factory_schematic" "latest_qemu_controlplane" {
  schematic = yamlencode({
    customization = {
      systemExtensions = {
        officialExtensions = data.talos_image_factory_extensions_versions.latest_qemu_controlplane.extensions_info.*.name
      }
    }
  })
}

data "talos_image_factory_urls" "latest_qemu_controlplane" {
  talos_version = local.talos_version_latest
  schematic_id  = talos_image_factory_schematic.latest_qemu_controlplane.id
  platform      = "nocloud"
}

output "talos_control_plane_update_command" {
  value = {for i, ip in var.k8_control_plain_list[*].ip_address: i => "talosctl upgrade --nodes ${ip} --image ${data.talos_image_factory_urls.latest_qemu_controlplane.urls.installer_secureboot}"}
}

#-------------------------------------------------------
# Talos Update Proxmox Workers
#-------------------------------------------------------
data "talos_image_factory_extensions_versions" "latest_qemu_worker" {
  talos_version = local.talos_version_latest
  filters = local.talos_qemu_worker_image_filters
}

resource "talos_image_factory_schematic" "latest_qemu_worker" {
  schematic = yamlencode({
    customization = {
      systemExtensions = {
        officialExtensions = data.talos_image_factory_extensions_versions.latest_qemu_worker.extensions_info.*.name
      }
    }
  })
}

data "talos_image_factory_urls" "latest_qemu_worker" {
  talos_version = local.talos_version_latest
  schematic_id  = talos_image_factory_schematic.latest_qemu_worker.id
  platform      = "nocloud"
}

output "talos_worker_update_command" {
  value = {for i, ip in var.k8_storage_node_list[*].ip_address: i => "talosctl upgrade --nodes ${ip} --image ${data.talos_image_factory_urls.latest_qemu_worker.urls.installer_secureboot}"}
}

#-------------------------------------------------------
# Talos Update Metal Control Planes
#-------------------------------------------------------
data "talos_image_factory_extensions_versions" "latest_metal_controlplane" {
  talos_version = local.talos_version_latest
}

resource "talos_image_factory_schematic" "latest_metal_controlplane" {
  schematic = yamlencode({
    customization = {
      systemExtensions = {}
    }
  })
}

data "talos_image_factory_urls" "latest_metal_controlplane" {
  talos_version = local.talos_version_latest
  schematic_id  = talos_image_factory_schematic.latest_metal_controlplane.id
  platform      = "metal"
}

output "talos_metal_control_plane_update_command" {
  value = {for i, v in var.k8_metal_control_list: i => "talosctl upgrade --nodes ${v.ip_address} --image ${data.talos_image_factory_urls.latest_metal_controlplane.urls.installer_secureboot}"}
}

#-------------------------------------------------------
# Talos Update Metal Workers
#-------------------------------------------------------
data "talos_image_factory_extensions_versions" "latest_metal_worker" {
  talos_version = local.talos_version_latest
  filters = local.talos_metal_worker_image_filters
}

resource "talos_image_factory_schematic" "latest_metal_worker" {
  schematic = yamlencode({
    customization = {
      systemExtensions = {
        officialExtensions = data.talos_image_factory_extensions_versions.latest_metal_worker.extensions_info.*.name
      }
    }
  })
}

data "talos_image_factory_urls" "latest_metal_worker" {
  talos_version = local.talos_version_latest
  schematic_id  = talos_image_factory_schematic.latest_metal_worker.id
  platform      = "metal"
}

output "talos_metal_worker_update_command" {
  value = {for i, v in var.k8_metal_worker_list: i => "talosctl upgrade --nodes ${v.ip_address} --image ${data.talos_image_factory_urls.latest_metal_worker.urls.installer_secureboot}"}
}
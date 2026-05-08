#-------------------------------------------------------
# Talos Control Plain Image Patch
#-------------------------------------------------------
locals {
  talos_control_plane_patch = {
    machine = {
      install = {
        disk  = "/dev/sda"
        image = data.talos_image_factory_urls.this.urls.installer
      }
    }
  }
}
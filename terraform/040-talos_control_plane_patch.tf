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
      network = {
        interfaces = [
          {
            interface = "eth0"
            dhcp      = false

            # HA Layer 2 VIP configuration
            vip = {
              ip = "192.168.0.227"
            }
          }
        ]
      }
      kubelet = {
        extraArgs = {
          rotate-server-certificates = true
        }
      }
    }
    cluster = {
      etcd = {
        extraArgs = {
          listen-metrics-urls = "http://0.0.0.0:2381"
        }
      }
    }
  }
}
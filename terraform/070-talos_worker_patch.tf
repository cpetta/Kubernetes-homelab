#-------------------------------------------------------
# Talos Worker Node Image Patch
#-------------------------------------------------------
locals {
  talos_storage_patch = {
    machine = {
      install = {
        disk  = "/dev/sda"
        image = data.talos_image_factory_urls.storage.urls.installer
      }
      disks = [
        {
          device = "/dev/sdb"
          partitions = [
            {
              mountpoint = "/var/lib/longhorn"
              size       = 0
            }
          ]
        },
      ]
      kubelet = {
        extraMounts = [
          {
            destination = "/var/lib/longhorn"
            type        = "bind"
            source      = "/var/lib/longhorn"
            options = [
              "bind",
              "rshared",
              "rw",
            ]
          }
        ]
      }
      sysctls = {
        "vm.nr_hugepages" = "1024"
      }
      kernel = {
        modules = [
          { name = "nvme_tcp" },
          { name = "vfio_pci" },
          { name = "nfsd" }
        ]
      }
    }
  }
}

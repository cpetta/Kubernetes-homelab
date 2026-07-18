#-------------------------------------------------------
# NFS - For Debug
#-------------------------------------------------------
locals {
  nfs = {
    version = "2.2.1"
    replicas = 0
    // Kiwix
    namespace   = "kiwix"
    export      = "/data *(rw,sync,no_subtree_check,no_acl,no_root_squash,fsid=0)"
    volume_name = "kiwix-stackoverflow-pvc"
    mount       = "/data"

    // Jellyfin Media
    # namespace   = "jellyfin"
    # export      = "/data *(rw,sync,no_subtree_check,no_acl,no_root_squash,fsid=0)"
    # volume_name = kubernetes_persistent_volume_claim_v1.jellyfin_media.metadata.0.name
    # mount       = "/data"

    // Jellyfin Config
    # namespace = "jellyfin"
    # export = "/etc/jellyfin-config *(rw,sync,no_subtree_check,fsid=0)"
    # volume_name = kubernetes_persistent_volume_claim_v1.jellyfin_config.metadata.0.name
    # mount = "/etc/jellyfin-config"

    // Traefik Data
    # namespace   = "traefik"
    # export      = "/mnt/traefik *(rw,sync,no_subtree_check,no_acl,fsid=0)"
    # volume_name = kubernetes_persistent_volume_claim_v1.traefik_data.metadata.0.name // "traefik-data-pvc"
    # mount       = "/mnt/traefik"

    // nextcloud
    # namespace   = "nextcloud"
    # export      = "/data *(rw,sync,no_subtree_check,no_acl,no_root_squash,fsid=0)"
    # volume_name = "nextcloud-config-pvc"
    # mount       = "/data"
  }
}

resource "kubernetes_deployment_v1" "nfs_server" {
  metadata {
    name      = "nfs-server"
    namespace = local.nfs.namespace
  }

  spec {
    replicas = local.nfs.replicas
    selector {
      match_labels = {
        app = "nfs-server"
      }
    }

    template {
      metadata {
        labels = {
          app = "nfs-server"
        }
      }

      spec {
        container {
          name  = "nfs-server"
          image = "erichough/nfs-server:${local.nfs.version}"

          env {
            name  = "NFS_PORT"
            value = "32049"
          }

          # env {
          #   name  = "NFS_LOG_LEVEL"
          #   value = "DEBUG"
          # }

          env { // Traefik Data
            name  = "NFS_EXPORT_0"
            value = local.nfs.export
          }

          port {
            name           = "nfs-tcp"
            container_port = 32049
            protocol       = "TCP"
          }

          port {
            name           = "nfs-udp"
            container_port = 32049
            protocol       = "UDP"
          }

          # Enable these ports for NFSv3 support
          # port {
          #   name = "mountd-tcp"
          #   container_port = 111
          #   protocol = "TCP"
          # }

          # port {
          #   name = "mountd-udp"
          #   container_port = 111
          #   protocol = "UDP"
          # }

          # port {
          #   name = "statd-in-tcp"
          #   container_port = 32765
          #   protocol = "TCP"
          # }

          # port {
          #   name = "statd-in-udp"
          #   container_port = 32765
          #   protocol = "UDP"
          # }

          # port {
          #   name = "statd-out-tcp"
          #   container_port = 32767
          #   protocol = "TCP"
          # }

          # port {
          #   name = "statd-out-udp"
          #   container_port = 32767
          #   protocol = "UDP"
          # }

          security_context {
            # privileged = true

            capabilities {
              add = [
                "SYS_ADMIN",
                "CAP_SYS_ADMIN",
              ]
            }
          }

          volume_mount {
            name       = local.nfs.volume_name
            mount_path = local.nfs.mount
          }

        }

        volume {
          name = local.nfs.volume_name
          persistent_volume_claim {
            claim_name = local.nfs.volume_name
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "nfs_service" {
  metadata {
    name      = "nfs"
    namespace = local.nfs.namespace
  }

  spec {
    selector = {
      app = "nfs-server"
    }

    port {
      name        = "nfs-tcp"
      port        = 2049
      protocol    = "TCP"
      target_port = 32049
    }

    port {
      name        = "nfs-udp"
      port        = 2049
      protocol    = "UDP"
      target_port = 32049
    }

    # Enable these ports for NFSv3 support  
    # port {
    #   name = "mountd-tcp"
    #   port = 111
    #   protocol = "TCP"
    # }

    # port {
    #   name = "mountd-udp"
    #   port = 111
    #   protocol = "UDP"
    # }

    # port {
    #   name = "statd-in-tcp"
    #   port = 32765
    #   protocol = "TCP"
    # }

    # port {
    #   name = "statd-in-udp"
    #   port = 32765
    #   protocol = "UDP"
    # }

    # port {
    #   name = "statd-out-tcp"
    #   port = 32767
    #   protocol = "TCP"
    # }

    # port {
    #   name = "statd-out-udp"
    #   port = 32767
    #   protocol = "UDP"
    # }

    type             = "LoadBalancer"
    load_balancer_ip = "192.168.0.246"
  }
  lifecycle {
    ignore_changes = [
      metadata
    ]
  }
}
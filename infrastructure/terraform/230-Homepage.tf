#-------------------------------------------------------
# Homepage - Config
#-------------------------------------------------------
locals {
  homepage = {
    version = "v1.13.2"
  }

}

#-------------------------------------------------------
# Homepage - Namespace
#-------------------------------------------------------
resource "kubernetes_namespace_v1" "homepage" {
  metadata {
    name = "homepage"
    labels = {}
  }
}

#-------------------------------------------------------
# Homepage - Cluster Account Config
#-------------------------------------------------------
resource "kubernetes_service_account_v1" "homepage" {
  metadata {
    name      = "homepage"
    namespace = kubernetes_namespace_v1.homepage.id
    labels    = {
      app = "homepage"
    }
  }

  secret {
    name = "homepage"
  }
}

resource "kubernetes_secret_v1" "homepage_service_account" {
  depends_on = [kubernetes_service_account_v1.homepage]
  type = "kubernetes.io/service-account-token"
  metadata {
    name      = "homepage"
    namespace = kubernetes_namespace_v1.homepage.id
    labels    = {
      app = "homepage"
    }

    annotations = {
      "kubernetes.io/service-account.name" = "homepage"
    }
  }
}

resource "kubernetes_cluster_role_v1" "homepage" {
  metadata {
    name   = "homepage"
    labels    = {
      app = "homepage"
    }
  }

  rule {
    api_groups = [""]
    resources  = ["namespaces", "pods", "nodes"]
    verbs      = ["get", "list"]
  }

  rule {
    api_groups = ["extensions", "networking.k8s.io"]
    resources  = ["ingresses"]
    verbs      = ["get", "list"]
  }

  rule {
    api_groups = ["traefik.io"]
    resources  = ["ingressroutes"]
    verbs      = ["get", "list"]
  }

  rule {
    api_groups = ["gateway.networking.k8s.io"]
    resources  = ["httproutes", "gateways"]
    verbs      = ["get", "list"]
  }

  rule {
    api_groups = ["metrics.k8s.io"]
    resources  = ["nodes", "pods"]
    verbs      = ["get", "list"]
  }
}

resource "kubernetes_cluster_role_binding_v1" "homepage" {
  depends_on = [kubernetes_service_account_v1.homepage]
  metadata {
    name   = "homepage"
    labels    = {
      app = "homepage"
    }
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind       = "ClusterRole"
    name       = kubernetes_cluster_role_v1.homepage.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.homepage.metadata[0].name
    namespace = kubernetes_namespace_v1.homepage.id
  }
}

#-------------------------------------------------------
# Homepage - Config Map
#-------------------------------------------------------
resource "kubernetes_config_map_v1" "homepage" {
  depends_on = [kubernetes_service_account_v1.homepage]
  metadata {
    name      = "homepage"
    namespace = kubernetes_namespace_v1.homepage.id
    labels    = {
      app = "homepage"
    }
  }

  data = {
    "settings.yaml" = <<-EOT
      theme: dark
      color: slate
      layout:
        Media:
          style: row
          columns: 4
      headerStyle: boxedWidgets
      base: https://${var.dns_zone}
      showStats: false # all docker or proxmox stats
      statusStyle: "dot"
      # disableCollapse: true
      providers:
        longhorn:
          url: http://longhorn-frontend.longhorn-system.svc.cluster.local:80
    EOT
    "kubernetes.yaml" = <<-EOT
      mode: cluster
      gateway: true # enable gateway-api
    EOT
    "docker.yaml" = ""
    "proxmox.yaml" = ""
    "custom.css" = ""
    "custom.js" = ""
    "custom.js" = ""

    "bookmarks.yaml" = <<-EOT
      - Bookmarks:
          - Backblaze:
              - abbr: BB
                icon: backblaze.png
                href: https://secure.backblaze.com/b2_buckets.htm
          - Github:
              - abbr: GH
                icon: github.png
                href: https://github.com/cpetta/Kubernetes-homelab
          - Codeberg:
              - abbr: CB
                icon: codeberg.png
                href: https://codeberg.org/chloegraves/kubernetes-homelab
          - Terriform Registry:
              - abbr: TR
                icon: terraform.png
                href: https://registry.terraform.io/
          - Artifact Hub:
              - abbr: AH
                icon: artifacthub.png
                href: https://artifacthub.io/
    EOT

    "services.yaml" = <<-EOT
      - Admin:
          - pm0:
              description: Proxmox Load Balanced
              icon: proxmox.png
              href: https://pm.${var.dns_zone}
              siteMonitor: https://pm.${var.dns_zone}
          - ns1:
              description: Technitium
              icon: technitium.png
              href: https://ns1.${var.dns_zone}:53443
              siteMonitor: https://ns1.${var.dns_zone}:53443
          - ns2:
              description: Technitium
              icon: technitium.png
              href: https://ns2.${var.dns_zone}:53443
              siteMonitor: https://ns2.${var.dns_zone}:53443
          - Vault:
              description: OpenBao
              icon: vault.png
              href: https://vault.${var.dns_zone}
              siteMonitor: https://vault.${var.dns_zone}
          # - crowdsec: # https://gethomepage.dev/widgets/services/crowdsec/
          #     widget:
          #     type: crowdsec
          #     url: http://crowdsechostorip:port
          #     username: localhost # machine_id in crowdsec
          #     password: password
          #     limit24h: true # optional, limits alerts to last 24h. Default: false
          # https://gethomepage.dev/widgets/services/customapi/
          # https://gethomepage.dev/widgets/services/dockhand/
          # https://gethomepage.dev/widgets/services/calendar/
          # https://gethomepage.dev/widgets/services/firefly/
          # https://gethomepage.dev/widgets/services/freshrss/
          # https://gethomepage.dev/widgets/services/gamedig/
          # https://gethomepage.dev/widgets/services/gitea/
          # https://gethomepage.dev/widgets/services/karakeep/
          # https://gethomepage.dev/widgets/services/homeassistant/
          # https://gethomepage.dev/widgets/services/homebox/
          # https://gethomepage.dev/widgets/services/homebridge/
          # https://gethomepage.dev/widgets/services/immich/
          # https://gethomepage.dev/widgets/services/jellyfin/
          # https://gethomepage.dev/widgets/services/lubelogger/
          # https://gethomepage.dev/widgets/services/minecraft/
          # https://gethomepage.dev/widgets/services/myspeed/
          # https://gethomepage.dev/widgets/services/navidrome/
          # https://gethomepage.dev/widgets/services/netdata/
          # https://gethomepage.dev/widgets/services/nextcloud/
          # https://gethomepage.dev/widgets/services/ntfy/
          # https://gethomepage.dev/widgets/services/opnsense/
          # https://gethomepage.dev/widgets/services/openwrt/
          # https://gethomepage.dev/widgets/services/pangolin/
          # https://gethomepage.dev/widgets/services/paperlessngx/
          # https://gethomepage.dev/widgets/services/pfsense/
          # https://gethomepage.dev/widgets/services/prometheus/
          # https://gethomepage.dev/widgets/services/prometheusmetric/
          # https://gethomepage.dev/widgets/services/proxmox/
          # https://gethomepage.dev/widgets/services/technitium/
          # https://gethomepage.dev/widgets/services/traefik/
      - Apps:
          # https://gethomepage.dev/widgets/services/grafana/
          # - grafana:
          #     widget:
          #       type: grafana
          #       version: 2 # optional, default is 1
          #       alerts: alertmanager # optional, default is grafana
          #       url: http://grafana.${var.dns_zone}
          #       username: admin
          #       password: ${var.grafana_password}
          #       totalalerts: true
          #       alertstriggered: true
          
          - EMail:
              description: Mailu Webmail
              icon: mailu.png
              href: https://mail.${var.dns_zone}/webmail
              siteMonitor: https://mail.${var.dns_zone}/webmail
          - EMail Admin:
              description: Mailu Admin
              icon: mailu.png
              href: https://mail.${var.dns_zone}/admin
              siteMonitor: https://mail.${var.dns_zone}/admin
    EOT

    "widgets.yaml" = <<-EOT
      - logo:
          icon: https://www.svgrepo.com/show/530679/gene-sequencing.svg
      - datetime:
          text_size: xl
          format:
            timeStyle: short
            hour12: true
      - datetime:
          text_size: xl
          format:
            dateStyle: short
      - openmeteo:
          label: Weather
          latitude: 42.93154
          longitude: -85.68632
          units: imperial # or metric
          cache: 60 # Time in minutes to cache API responses, to stay within limits
          # format: # optional, Intl.NumberFormat options
          maximumFractionDigits: 1
      - kubernetes:
          cluster:
            show: true
            cpu: true
            memory: true
            showLabel: true
            label: "Cluster"
          nodes:
            show: false
            cpu: false
            memory: false
            showLabel: false
      - longhorn:
          expanded: true
          total: true
          labels: true
          nodes: false
      # - resources:
      #     backend: resources
      #     expanded: true
      #     cpu: true
      #     memory: true
      #     network: default
      - search:
          provider: duckduckgo
          target: _blank
    EOT
  }
}

#-------------------------------------------------------
# Homepage - deployment
#-------------------------------------------------------
resource "kubernetes_deployment_v1" "homepage" {
  depends_on = [
    kubernetes_service_account_v1.homepage,
    kubernetes_config_map_v1.homepage,
    kubernetes_service_v1.homepage,
  ]
  metadata {
    name      = "homepage"
    namespace = kubernetes_namespace_v1.homepage.id
    
    labels    = {
      app = "homepage"
    }
  }

  spec {
    replicas                 = 1
    revision_history_limit   = 3

    selector {
      match_labels = {
        app = "homepage"
      }
    }

    strategy {
      type = "RollingUpdate"
    }

    template {
      metadata {
        labels    = {
          app = "homepage"
        }
      }

      spec {
        service_account_name              = kubernetes_service_account_v1.homepage.metadata[0].name
        automount_service_account_token   = true
        dns_policy                        = "ClusterFirst"
        enable_service_links              = true

        container {
          name              = "homepage"
          image             = "ghcr.io/gethomepage/homepage:${local.homepage.version}"
          image_pull_policy = "IfNotPresent"

          security_context {
            allow_privilege_escalation = false
            run_as_non_root            = true
            run_as_user                = 1000
            run_as_group               = 1000

            capabilities {
              drop = ["ALL"]
            }

            seccomp_profile {
              type = "RuntimeDefault"
            }
          }

          env {
            name = "MY_POD_IP"

            value_from {
              field_ref {
                field_path = "status.podIP"
              }
            }
          }

          env {
            name  = "HOMEPAGE_ALLOWED_HOSTS"
            # value = "*"
            value = "$(MY_POD_IP):3000,${var.dns_zone},"
          }

          port {
            name           = "http"
            container_port = 3000
          }

          liveness_probe {
            http_get {
              path = "/api/healthcheck"
              port = "http"
            }

            initial_delay_seconds = 5
            period_seconds        = 15
          }

          volume_mount {
            name       = "homepage-config"
            mount_path = "/app/config/custom.js"
            sub_path   = "custom.js"
          }

          volume_mount {
            name       = "homepage-config"
            mount_path = "/app/config/custom.css"
            sub_path   = "custom.css"
          }

          volume_mount {
            name       = "homepage-config"
            mount_path = "/app/config/bookmarks.yaml"
            sub_path   = "bookmarks.yaml"
          }

          volume_mount {
            name       = "homepage-config"
            mount_path = "/app/config/docker.yaml"
            sub_path   = "docker.yaml"
          }

          volume_mount {
            name       = "homepage-config"
            mount_path = "/app/config/kubernetes.yaml"
            sub_path   = "kubernetes.yaml"
          }

          volume_mount {
            name       = "homepage-config"
            mount_path = "/app/config/services.yaml"
            sub_path   = "services.yaml"
          }

          volume_mount {
            name       = "homepage-config"
            mount_path = "/app/config/settings.yaml"
            sub_path   = "settings.yaml"
          }

          volume_mount {
            name       = "homepage-config"
            mount_path = "/app/config/widgets.yaml"
            sub_path   = "widgets.yaml"
          }

          volume_mount {
            name       = "homepage-config"
            mount_path = "/app/config/proxmox.yaml"
            sub_path   = "proxmox.yaml"
          }

          volume_mount {
            name       = "logs"
            mount_path = "/app/config/logs"
          }
        }

        volume {
          name = "homepage-config"

          config_map {
            name = kubernetes_config_map_v1.homepage.metadata[0].name
          }
        }

        volume {
          name = "logs"

          empty_dir {}
        }
      }
    }
  }
}

#-------------------------------------------------------
# Homepage - Service
#-------------------------------------------------------
resource "kubernetes_service_v1" "homepage" {
  metadata {
    name      = "homepage"
    namespace = kubernetes_namespace_v1.homepage.id

    labels    = {
      app = "homepage"
    }
  }

  spec {
    type = "ClusterIP"
    selector = {
      app = "homepage"
    }

    port {
      name        = "http"
      port        = 3000
      target_port = "http"
      protocol    = "TCP"
    }
  }
}

#-------------------------------------------------------
# Homepage - DNS
#-------------------------------------------------------
resource "dns_a_record_set" "homepage" {
  zone     = "${var.dns_zone}."
  # name     = ""
  addresses = [
    var.k8_service_list.rp,
  ]
}

resource "kubernetes_manifest" "homepage_httproute" {
  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "HTTPRoute"

    metadata = {
      name      = "homepage"
      namespace = kubernetes_namespace_v1.homepage.id
    }

    spec = {
      hostnames = [
        "${var.dns_zone}"
      ]
      parentRefs = [
        {
          name = "traefik-gateway"
          namespace = "traefik"
        },
      ]
      rules = [
        {
          backendRefs = [
            {
              name = "homepage"
              namespace = kubernetes_namespace_v1.homepage.id
              port = 3000
            }
          ]
          matches = [
            {
              path = {
                type  = "PathPrefix"
                value = "/"
              }
            },
          ]
        }
      ]
    }
  }
}

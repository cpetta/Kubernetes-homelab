#-------------------------------------------------------
# Kubernetes - DNS
#-------------------------------------------------------
resource "kubernetes_namespace_v1" "dns_server" {
  metadata {
    name = "dns-server"
    labels = {}
  }
}

resource "kubernetes_manifest" "dns_config_longhorn_volume" {
  for_each = { for i, v in var.k8_dns_server_list : i => v }
  manifest = {
    apiVersion = "longhorn.io/v1beta2"
    kind       = "Volume"

    metadata = {
      name      = "dns-config-volume-${each.key}"
      namespace = "longhorn-system"
    }

    spec = {
      size             = "1073741824" # 1Gi in bytes
      numberOfReplicas = each.value.volume_replicas
      frontend         = "blockdev"
      accessMode       = "rwo" // "rwo"
      dataLocality     = "best-effort" // "strict-local"
    }
  }
}

resource "kubernetes_persistent_volume_v1" "dns_config" {
  for_each = { for i, v in var.k8_dns_server_list : i => v }
  depends_on = [kubernetes_manifest.dns_config_longhorn_volume]
  metadata {
    name = "dns-config-${each.key}"
  }

  spec {
    storage_class_name = "longhorn"
    access_modes       = ["ReadWriteOnce"] // ["ReadWriteMany"]

    capacity = {
      storage = "1Gi"
    }

    persistent_volume_source {
      csi {
        driver        = "driver.longhorn.io"
        volume_handle = kubernetes_manifest.dns_config_longhorn_volume[each.key].manifest.metadata.name
      }
    }
  }
  lifecycle {
    ignore_changes = [
      metadata
    ]
  }
}

resource "kubernetes_persistent_volume_claim_v1" "dns_config" {
  for_each = { for i, v in var.k8_dns_server_list : i => v }
  depends_on = [kubernetes_persistent_volume_v1.dns_config ]
  metadata {
    name      = "dns-config-pvc-${each.key}"
    namespace = kubernetes_namespace_v1.dns_server.id
  }

  spec {
    volume_name = kubernetes_persistent_volume_v1.dns_config[each.key].metadata.0.name
    access_modes = ["ReadWriteOnce"] // ["ReadWriteMany"]
    
    resources {
      requests = {
        storage = "1Gi"
      }
    }
  }
}

resource "kubernetes_deployment_v1" "dns_server" {
  for_each = { for i, v in var.k8_dns_server_list : i => v }
  depends_on = [ kubernetes_persistent_volume_claim_v1.dns_config ]
  metadata {
    name      = "dns-server-${each.key}"
    namespace = kubernetes_namespace_v1.dns_server.id
  }

  spec {
    replicas = each.value.replicas // local.update_mode ? 0 : each.value.replicas
    selector {
      match_labels = {
        app = "dns-server-${each.key}"
      }
    }

    strategy {
      type = "Recreate"
    }

    template {
      metadata {
        labels = {
          app = "dns-server-${each.key}"
        }
      }
      
      spec {
        affinity {
          pod_anti_affinity {
            required_during_scheduling_ignored_during_execution {
              topology_key = "kubernetes.io/hostname"
              label_selector {
                match_expressions {
                  key = "app"
                  operator = "In"
                  values = [
                    "dns-server-primary",
                    "dns-server-secondary-1",
                  ]
                }
              }
            }
          }
        }

        container {
          name  = "dns-server-${each.key}"
          image = "technitium/dns-server:latest"

          #The primary domain name used by this DNS Server to identify itself.
          env { 
            name  = "DNS_SERVER_DOMAIN"
            value = "ns${each.key}"
          }

          #DNS web console admin user password.
          env {
            name  = "DNS_SERVER_ADMIN_PASSWORD"
            value = var.dns_password
          }

          #Comma separated list of network interface IP addresses that you want the web service to listen on for requests. The "172.17.0.1" address is the built-in Docker bridge. The "[::]" is the default value if not>
          env {
            name  = "DNS_SERVER_WEB_SERVICE_LOCAL_ADDRESSES"
            value = "127.0.0.1, 172.17.0.1, 172.18.0.1"
          }

          #The TCP port number for the DNS web console over HTTP protocol.
          env {
            name  = "DNS_SERVER_WEB_SERVICE_HTTP_PORT"
            value = 5380
          }

          #The TCP port number for the DNS web console over HTTPS protocol.
          env {
            name  = "DNS_SERVER_WEB_SERVICE_HTTPS_PORT"
            value = 53443
          }

          #Enables HTTPS for the DNS web console.
          env {
            name  = "DNS_SERVER_WEB_SERVICE_ENABLE_HTTPS"
            value = true
          }

          #Enables self signed TLS certificate for the DNS web console.
          env {
            name  = "DNS_SERVER_WEB_SERVICE_USE_SELF_SIGNED_CERT"
            value = true
          }

          #The file path to the TLS certificate for the DNS web console.
          env {
            name  = "DNS_SERVER_WEB_SERVICE_TLS_CERTIFICATE_PATH"
            value = "/etc/dns/tls/cert.pfx"
          }

          #The password for the TLS certificate for the DNS web console.
          env {
            name  = "DNS_SERVER_WEB_SERVICE_TLS_CERTIFICATE_PASSWORD"
            value = var.dns_cert_password
          }

          #Enables HTTP to HTTPS redirection for the DNS web console.
          env {
            name  = "DNS_SERVER_WEB_SERVICE_HTTP_TO_TLS_REDIRECT"
            value = false
          }

          #Comma separated list of IP addresses or network addresses to allow recursion. Valid only for `UseSpecifiedNetworkACL` recursion option.  This option is obsolete and DNS_SERVER_RECURSION_NETWORK_ACL should b>
          env {
            name  = "DNS_SERVER_RECURSION_ALLOWED_NETWORKS"
            value = "127.0.0.1, 192.168.0.0/24"
          }

          #Sets the DNS server to block domain names using Blocked Zone and Block List Zone.
          env {
            name  = "DNS_SERVER_ENABLE_BLOCKING"
            value = true
          }

          # Block Lists
          env {
            name  = "DNS_SERVER_BLOCK_LIST_URLS"
            value = "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts,https://raw.githubusercontent.com/Firestorrrm/Minimal-Hosts-Blocker/master/iosadlist.txt,https://raw.githubusercontent.com/PolishFiltersTeam/KADhosts/master/KADhosts.txt,https://raw.githubusercontent.com/FadeMind/hosts.extras/master/add.Spam/hosts,https://v.firebog.net/hosts/static/w3kbl.txt,https://adaway.org/hosts.txt,https://v.firebog.net/hosts/AdguardDNS.txt,https://v.firebog.net/hosts/Admiral.txt,https://raw.githubusercontent.com/anudeepND/blacklist/master/adservers.txt,https://v.firebog.net/hosts/Easylist.txt,https://pgl.yoyo.org/adservers/serverlist.php?hostformat=hosts&showintro=0&mimetype=plaintext,https://raw.githubusercontent.com/FadeMind/hosts.extras/master/UncheckyAds/hosts,https://raw.githubusercontent.com/bigdargon/hostsVN/master/hosts,https://v.firebog.net/hosts/Easyprivacy.txt,https://v.firebog.net/hosts/Prigent-Ads.txt,https://raw.githubusercontent.com/FadeMind/hosts.extras/master/add.2o7Net/hosts,https://raw.githubusercontent.com/crazy-max/WindowsSpyBlocker/master/data/hosts/spy.txt,https://hostfiles.frogeye.fr/firstparty-trackers-hosts.txt,https://raw.githubusercontent.com/DandelionSprout/adfilt/master/Alternate%20versions%20Anti-Malware%20List/AntiMalwareHosts.txt,https://v.firebog.net/hosts/Prigent-Crypto.txt,https://raw.githubusercontent.com/FadeMind/hosts.extras/master/add.Risk/hosts,https://phishing.army/download/phishing_army_blocklist_extended.txt,https://gitlab.com/quidsup/notrack-blocklists/raw/master/notrack-malware.txt,https://raw.githubusercontent.com/Spam404/lists/master/main-blacklist.txt,https://raw.githubusercontent.com/AssoEchap/stalkerware-indicators/master/generated/hosts,https://urlhaus.abuse.ch/downloads/hostfile/,https://lists.cyberhost.uk/malware.txt,https://malware-filter.gitlab.io/malware-filter/phishing-filter-hosts.txt,https://v.firebog.net/hosts/Prigent-Malware.txt,https://raw.githubusercontent.com/jarelllama/Scam-Blocklist/main/lists/wildcard_domains/scams.txt,https://v.firebog.net/hosts/RPiList-Malware.txt,https://v.firebog.net/hosts/RPiList-Phishing.txt,https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/gambling/hosts,https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/wildcard/pro-onlydomains.txt"
          }

          #Comma separated list of forwarder addresses.
          env {
            name  = "DNS_SERVER_FORWARDERS"
            value = "1.1.1.1, 1.0.0.1, 9.9.9.9, 149.112.112.112, 208.67.222.222, 208.67.220.220"
          }

          # ------------
          # Ports
          # ------------

          #DNS web console (HTTP)
          port {
            name           = "web-http"
            container_port = 5380
            protocol       = "TCP"
          }

          #DNS web console (HTTPS)
          port {
            name           = "web-https"
            container_port = 53443
            protocol       = "TCP"
          }

          #DNS service tcp
          port {
            name           = "dns-tcp"
            container_port = 53
            protocol       = "TCP"
          }
          port {
            name           = "dns-udp"
            container_port = 53
            protocol       = "UDP"
          }

          #DNS-over-QUIC service
          # port {
          #   name           = "quic-udp"
          #   container_port = 853
          #   protocol       = "UDP"
          # }
          
          # # #DNS-over-TLS service
          # port {
          #   name           = "tls-tcp"
          #   container_port = 853
          #   protocol       = "TCP"
          # }

          # # #DNS-over-HTTPS service
          # port {
          #   name           = "http-1-2"
          #   container_port = 443
          #   protocol       = "TCP"
          # }
          # port {
          #   name           = "http-3"
          #   container_port = 443
          #   protocol       = "UDP"
          # }

          # # #DNS-over-HTTP service (use with reverse proxy or certbot certificate renewal)
          # port {
          #   name           = "dns-http"
          #   container_port = 80
          #   protocol       = "TCP"
          # }



          #DNS-over-HTTP service (use with reverse proxy)
          # port {
          #   name           = "http"
          #   container_port = 8053
          #   protocol       = "TCP"
          # }

          volume_mount {
            name       = kubernetes_persistent_volume_claim_v1.dns_config[each.key].metadata.0.name
            mount_path = "/etc/dns"
          }

        }

        volume {
          name = kubernetes_persistent_volume_claim_v1.dns_config[each.key].metadata.0.name
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.dns_config[each.key].metadata.0.name
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "dns_dashboard_service" {
  for_each = { for i, v in var.k8_dns_server_list : i => v }
  metadata {
    name      = "dns-dashboard-${each.key}"
    namespace = kubernetes_namespace_v1.dns_server.id
  }

  spec {
    type = "ClusterIP"
    selector = {
      app = "dns-server-${each.key}"
    }

    port {
      name        = "dash-http"
      port        = 5380
      protocol    = "TCP"
      target_port = 5380
    }

    port {
      name        = "dash-https"
      port        = 53443
      protocol    = "TCP"
      target_port = 53443
    }
  }

  lifecycle {
    ignore_changes = [
      metadata
    ]
  }
}

resource "kubernetes_service_v1" "dns_service" {
  metadata {
    name = "dns-server-service"
    namespace = kubernetes_namespace_v1.dns_server.id
  }

  spec {
    selector = {
      app = "dns-server"
    }

    port {
      name        = "dns-tcp"
      port        = 53
      protocol    = "TCP"
      target_port = 53
    }

    port {
      name        = "dns-udp"
      port        = 53
      protocol    = "UDP"
      target_port = 53
    }

    type             = "LoadBalancer"
    load_balancer_ip = "192.168.0.250"
  }

  lifecycle {
    ignore_changes = [
      metadata
    ]
  }
}

resource "kubernetes_manifest" "dns_dashboard_http_route" {
  for_each = { for i, v in var.k8_dns_server_list : i => v }
  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1"
    kind = "HTTPRoute"
    metadata = {
      name = "dns-dashboard-${each.key}"
      namespace = kubernetes_namespace_v1.traefik.id
    }
    spec = {
      hostnames = [
        "dns${each.key}.${var.dns_zone}",
      ]
      parentRefs = [
        {
          name = "traefik-gateway"
        },
      ]
      rules = [
        {
          backendRefs = [
            {
              name = "dns-dashboard-${each.key}"
              namespace = kubernetes_namespace_v1.dns_server.id
              port = 5380
            },
          ]
          matches = [
            {
              path = {
                type = "PathPrefix"
                value = "/"
              }
            },
          ]
        },
      ]
    }
  }
}

resource "kubernetes_manifest" "referencegrant_dns_server" {
  for_each = { for i, v in var.k8_dns_server_list : i => v }
  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1beta1"
    kind = "ReferenceGrant"
    metadata = {
      name = "dns-dashboard--${each.key}"
      namespace = kubernetes_namespace_v1.dns_server.id
    }
    spec = {
      from = [
        {
          group = "gateway.networking.k8s.io"
          kind = "HTTPRoute"
          namespace = kubernetes_namespace_v1.traefik.id
        },
      ]
      to = [
        {
          group = ""
          kind = "Service"
          name = "dns-dashboard-${each.key}"
        },
      ]
    }
  }
}
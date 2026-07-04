#-------------------------------------------------------
# Kubernetes - proxmox namespace
#-------------------------------------------------------
resource "kubernetes_namespace_v1" "proxmox" {
  metadata {
    name = "proxmox"
  }
}

resource "kubernetes_service_v1" "proxmox" {
  for_each = { for i, v in var.pm_node_list : v.name => v }
  metadata {
    name      = each.key
    namespace = kubernetes_namespace_v1.proxmox.id
    annotations = {
      "traefik.io/service.nativelb" = "true"
    }
  }

  spec {
    port {
      name        = "web"
      port        = 443
      protocol    = "TCP"
      target_port = 8006
    }
  }

  lifecycle {
    ignore_changes = [
      metadata
    ]
  }
}

resource "kubernetes_endpoint_slice_v1" "proxmox" {
  for_each = { for i, v in var.pm_node_list : v.name => v }
  address_type = "IPv4"
  
  metadata {
    name = "${each.value.name}"
    namespace = kubernetes_namespace_v1.proxmox.id
    labels = {
      "kubernetes.io/service-name" = each.key
    }
  }

  endpoint {
    condition {
      ready = true
    }
    addresses = [each.value.ip_address]
  }

  port {
    name = "web"
    port = 8006
    app_protocol = "http"
    protocol = "TCP"
  }
}

#-------------------------------------------------------
# Kubernetes - HTTP Route for each endpoint
#-------------------------------------------------------
resource "kubernetes_manifest" "proxmox_http_route" {
  for_each = { for i, v in var.pm_node_list : v.name => v }
  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "HTTPRoute"
    metadata = {
      name      = each.value.name
      namespace = "traefik"

      annotations = {
        "gethomepage.dev/enabled" = "true"
        "gethomepage.dev/name" = each.value.name
        "gethomepage.dev/description" = "Proxmox"
        "gethomepage.dev/icon" = "proxmox.png"
        "gethomepage.dev/group" = "Admin"
        "gethomepage.dev/pod-selector" = ""
        "gethomepage.dev/siteMonitor" = "https://${each.value.name}.${var.dns_zone}"
      }
    }
    spec = {
      hostnames = [
        "${each.value.name}.${var.dns_zone}",
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
              name      = kubernetes_service_v1.proxmox[each.key].metadata.0.name
              namespace = kubernetes_namespace_v1.proxmox.id
              port      = 443
            },
          ]
          matches = [
            {
              path = {
                type  = "PathPrefix"
                value = "/"
              }
            },
          ]
        },
      ]
    }
  }
}

resource "kubernetes_manifest" "proxmox_reference_grant" {
  for_each = { for i, v in var.pm_node_list : v.name => v }
  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1beta1"
    kind       = "ReferenceGrant"
    metadata = {
      name      = each.value.name
      namespace = kubernetes_namespace_v1.proxmox.id
    }
    spec = {
      from = [
        {
          group     = "gateway.networking.k8s.io"
          kind      = "HTTPRoute"
          namespace = "traefik"
        },
      ]
      to = [
        {
          group = ""
          kind  = "Service"
          name  = kubernetes_service_v1.proxmox[each.key].metadata.0.name
        },
      ]
    }
  }
}

#-------------------------------------------------------
# Kubernetes - Load Ballanced route
#-------------------------------------------------------
resource "kubernetes_manifest" "load_ballance_pm_traefik_service" {
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "TraefikService"
    metadata = {
      name      = "pmlb"
      namespace = kubernetes_namespace_v1.proxmox.id
    }
    spec = {
      weighted = {
        services = [
          for v in var.pm_node_list : {
            name = v.name
            namespace = kubernetes_namespace_v1.proxmox.id
            nativeLB = true
            port = 443
            weight = 1
            sticky = {
              cookie = {
                name: "pmlbL2"
              }
            }
          }
        ]
        sticky = {
          cookie = {
            name: "pmlbL1"
          }
        }
      }
    }
  }
}

resource "kubernetes_manifest" "load_ballance_pm_ingress" {
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "pmlbingress"
      namespace = kubernetes_namespace_v1.proxmox.id
    }
    spec = {
      entryPoints = [
        "web",
        "websecure",
      ]
      
      routes = [
        {
          match = "Host(`pm.${var.dns_zone}`) && PathPrefix(`/`)"
          kind = "Rule"
          services = [
            {
              name = "pmlb"
              namespace = kubernetes_namespace_v1.proxmox.id
              kind = "TraefikService"
            }
          ]
        }
      ]
    }
  }
}

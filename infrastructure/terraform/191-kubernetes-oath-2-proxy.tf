#-------------------------------------------------------
# KeyCloak - Middlewares
#-------------------------------------------------------
resource "kubernetes_manifest" "auth_headers_middleware" {
  for_each = { for i, v in var.oauth_services : i => v }
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind = "Middleware"
    metadata = {
      name = "auth-headers-${each.value.name}"
      namespace = each.value.namespace
    }
    spec = {
      headers = {
        sslRedirect = true
        stsSeconds = 315360000
        browserXssFilter = true
        contentTypeNosniff = true
        forceSTSHeader = true
        sslHost = var.dns_zone
        stsIncludeSubdomains = true
        stsPreload = true
        frameDeny = true
      }
    }
  }
}

resource "kubernetes_manifest" "oauth_auth_redirect_auth_middleware" {
  for_each = { for i, v in var.oauth_services : i => v }
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind = "Middleware"
    metadata = {
      name = "${each.value.name}-oauth-redirect"
      namespace = each.value.namespace
    }
    spec = {
      forwardAuth = {
        address = "http://oauth2-proxy-${each.value.name}.${each.value.namespace}.svc.cluster.local:80"
        trustForwardHeader = true
        maxResponseBodySize = 1048576
        maxBodySize = 1048576
        authResponseHeaders = [
          "X-Auth-Request-Access-Token",
          "Authorization",
        ]
      }
    }
  }
}

#-------------------------------------------------------
# Oauth2 Proxy - Helm
#-------------------------------------------------------
resource "helm_release" "oauth2proxy" {
  for_each = { for i, v in var.oauth_services : i => v }
  name             = "oauth2-proxy-${each.value.name}"
  namespace        = each.value.namespace
  create_namespace = false
  repository       = "https://oauth2-proxy.github.io/manifests"
  chart            = "oauth2-proxy"
  version          = "10.4.3"

  values = [
    jsonencode(yamldecode(templatefile("${path.module}/helm/templates/oauth2proxy.tftpl", {
      dns_zone = var.dns_zone
      subnet = each.value.subnet
      client_id = each.value.client_id
      client_secret = each.value.client_secret
      roles = each.value.roles
      realm = each.value.realm
      email_domain = var.dns_zone
    })))
  ]
}

#-------------------------------------------------------
# Oauth2 Proxy - Helm
#-------------------------------------------------------
resource "kubernetes_manifest" "oauth_httproute_redirect" {
  for_each = { for i, v in var.oauth_services : i => v if i != "traefik"}
  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "HTTPRoute"
    metadata = {
      name      = each.value.name
      namespace = each.value.namespace
    }
    spec = {
      hostnames = [
        "${each.value.subnet}.${var.dns_zone}",
      ]
      parentRefs = [
        {
          name = "traefik-gateway"
          namespace = kubernetes_namespace_v1.traefik.id
        },
      ]
      rules = [
        {
          backendRefs = [
            {
              name      = each.value.service_name
              namespace = each.value.namespace
              port      = each.value.port
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
          filters = [
            {
              type = "ExtensionRef"
              extensionRef = {
                group = "traefik.io"
                kind = "Middleware"
                name = "${each.value.name}-oauth-redirect"
              }
            },
          ]
        },
      ]
    }
  }
}

resource "kubernetes_manifest" "oauth_httproute" {
  for_each = { for i, v in var.oauth_services : i => v }
  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "HTTPRoute"
    metadata = {
      name      = "${each.value.name}-oauth"
      namespace = each.value.namespace

      annotations = {
        "gethomepage.dev/enabled" = "true"
        "gethomepage.dev/name" = each.value.homepage_name
        "gethomepage.dev/description" = each.value.homepage_desc
        "gethomepage.dev/icon" = each.value.homepage_logo
        "gethomepage.dev/group" = each.value.homepage_group
        "gethomepage.dev/href" = "https://${each.value.subnet}.${var.dns_zone}"
        "gethomepage.dev/pod-selector" = each.value.homepage_pod
        "gethomepage.dev/siteMonitor" = "https://${each.value.subnet}.${var.dns_zone}"
      }
    }
    spec = {
      hostnames = [
        "${each.value.subnet}.${var.dns_zone}",
      ]
      parentRefs = [
        {
          name = "traefik-gateway"
          namespace = kubernetes_namespace_v1.traefik.id
        },
      ]
      rules = [
        {
          backendRefs = [
            {
              name      = "oauth2-proxy-${each.value.name}"
              namespace = each.value.namespace
              port      = 80
            },
          ]
          matches = [
            {
              path = {
                type  = "PathPrefix"
                value = "/oauth2/"
              }
            },
          ]
          filters = [
            {
              type = "ExtensionRef"
              extensionRef = {
                group = "traefik.io"
                kind = "Middleware"
                name = "auth-headers-${each.value.name}"
              }
            },
          ]
        },
      ]
    }
  }
}
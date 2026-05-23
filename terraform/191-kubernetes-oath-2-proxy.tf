#-------------------------------------------------------
# KeyCloak - Middlewares
#-------------------------------------------------------
resource "kubernetes_manifest" "auth_headers_middleware" {
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind = "Middleware"
    metadata = {
      name = "auth-headers"
      namespace = kubernetes_namespace_v1.traefik.id
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
      namespace = kubernetes_namespace_v1.traefik.id
    }
    spec = {
      forwardAuth = {
        address = "http://oauth2-proxy-${each.value.name}.traefik.svc.cluster.local:80"
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
  namespace        = kubernetes_namespace_v1.traefik.id
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
      namespace = "traefik"
    }
    spec = {
      hostnames = [
        "${each.value.subnet}.${var.dns_zone}",
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
      namespace = kubernetes_namespace_v1.traefik.id
    }
    spec = {
      hostnames = [
        "${each.value.subnet}.${var.dns_zone}",
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
              name      = "oauth2-proxy-${each.value.name}"
              namespace = kubernetes_namespace_v1.traefik.id
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
                name = "auth-headers"
              }
            },
          ]
        },
      ]
    }
  }
}

resource "kubernetes_manifest" "oauth_reference_grant" {
  for_each = { for i, v in var.oauth_services : i => v }
  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1beta1"
    kind       = "ReferenceGrant"
    metadata = {
      name      = each.value.name
      namespace = each.value.namespace
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
          name  = each.value.service_name
        },
      ]
    }
  }
}
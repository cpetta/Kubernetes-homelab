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
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind = "Middleware"
    metadata = {
      name = "oauth-auth-redirect"
      namespace = kubernetes_namespace_v1.traefik.id
    }
    spec = {
      forwardAuth = {
        address = "http://oauth2-proxy.traefik.svc.cluster.local:80"
        trustForwardHeader = true
        authResponseHeaders = [
          "X-Auth-Request-Access-Token",
          "Authorization",
        ]
      }
    }
  }
}

# resource "kubernetes_manifest" "oauth_auth_wo_redirect_middleware" {
#   manifest = {
#     apiVersion = "traefik.io/v1alpha1"
#     kind = "Middleware"
#     metadata = {
#       name = "oauth-auth-wo-redirect"
#       namespace = kubernetes_namespace_v1.traefik.id
#     }
#     spec = {
#       forwardAuth = {
#         address = "https://oauth.${var.dns_zone}/oauth2/auth"
#         trustForwardHeader = true
#         authResponseHeaders = [
#           "X-Auth-Request-Access-Token",
#           "Authorization",
#         ]
#       }
#     }
#   }
# }


resource "kubernetes_manifest" "oauth_http_route" {
  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "HTTPRoute"
    metadata = {
      name      = "oauth-http-route"
      namespace = kubernetes_namespace_v1.traefik.id
    }
    spec = {
      hostnames = [
        "oauth.${var.dns_zone}",
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
              name      = "oauth2-proxy"
              namespace = kubernetes_namespace_v1.traefik.id
              port      = 80
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
                name = "auth-headers"
              }
            },
          ]
        },
      ]
    }
  }
}

#-------------------------------------------------------
# Oauth2 Proxy - Helm
#-------------------------------------------------------
resource "helm_release" "oauth2proxy" {
  depends_on = [kubernetes_persistent_volume_claim_v1.postgres]
  name             = "oauth2-proxy"
  namespace        = kubernetes_namespace_v1.traefik.id
  create_namespace = false
  repository       = "https://oauth2-proxy.github.io/manifests"
  chart            = "oauth2-proxy"
  version          = "10.4.3"

  values = [
    jsonencode(yamldecode(templatefile("${path.module}/helm/templates/oauth2proxy.tftpl", {
      dns_zone = var.dns_zone
      client_id = var.oauth2_client_id
      client_secret = var.oauth2_client_secret
    })))
  ]
}
#-------------------------------------------------------
# Kubernetes - Storage
#-------------------------------------------------------
resource "kubernetes_namespace_v1" "storage" {
  metadata {
    name = "longhorn-system"
    labels = {
      "pod-security.kubernetes.io/enforce"         = "privileged"
      "pod-security.kubernetes.io/enforce-version" = "latest"
      "pod-security.kubernetes.io/audit"           = "privileged"
      "pod-security.kubernetes.io/audit-version"   = "latest"
      "pod-security.kubernetes.io/warn"            = "privileged"
      "pod-security.kubernetes.io/warn-version"    = "latest"
    }
  }
}

resource "helm_release" "longhorn" {
  name              = "longhorn"
  namespace         = kubernetes_namespace_v1.storage.id
  create_namespace  = false
  repository        = "https://charts.longhorn.io"
  chart             = "longhorn"
  version           = "1.9.0"
  dependency_update = true
  force_update      = true
  take_ownership    = true
  reset_values      = true
  # atomic          = true
  # cleanup_on_fail = true
}

resource "kubernetes_manifest" "longhorn_dashboard_http_route" {
  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "HTTPRoute"
    metadata = {
      name      = "longhorn-http-route"
      namespace = kubernetes_namespace_v1.traefik.id
    }
    spec = {
      hostnames = [
        "longhorn.${var.dns_zone}",
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
              name      = "longhorn-frontend"
              namespace = kubernetes_namespace_v1.storage.id
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
        },
      ]
    }
  }
}

resource "kubernetes_manifest" "referencegrant_longhorn_dashboard" {
  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1beta1"
    kind       = "ReferenceGrant"
    metadata = {
      name      = "longhorn-reference-grant"
      namespace = kubernetes_namespace_v1.storage.id
    }
    spec = {
      from = [
        {
          group     = "gateway.networking.k8s.io"
          kind      = "HTTPRoute"
          namespace = kubernetes_namespace_v1.traefik.id
        },
      ]
      to = [
        {
          group     = ""
          kind      = "Service"
          name      = "longhorn-frontend"
          namespace = kubernetes_namespace_v1.storage.id
        },
      ]
    }
  }
}
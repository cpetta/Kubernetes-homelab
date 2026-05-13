#-------------------------------------------------------
# Kubernetes - Metrics
#-------------------------------------------------------
locals {
  metrics_services = {
    grafana = {
      name         = "metrics-grafana"
      service_name = "kube-prometheus-stack-grafana"
      subnet       = "grafana"
      port         = 80
    }
  }
}

resource "kubernetes_namespace_v1" "metrics" {
  metadata {
    name = "metrics"
    labels = {
      #   "pod-security.kubernetes.io/enforce" = "privileged"
    }
  }
}

resource "helm_release" "kube_prometheus_stack" {
  name       = "kube-prometheus-stack"
  namespace  = kubernetes_namespace_v1.metrics.id
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
}

resource "kubernetes_manifest" "Metrics_HTTP_Route" {
  for_each = { for i, v in local.metrics_services : i => v }
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
              namespace = kubernetes_namespace_v1.metrics.id
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
        },
      ]
    }
  }
}

resource "kubernetes_manifest" "Metrics_Reference_Grant" {
  for_each = { for i, v in local.metrics_services : i => v }
  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1beta1"
    kind       = "ReferenceGrant"
    metadata = {
      name      = each.value.name
      namespace = kubernetes_namespace_v1.metrics.id
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
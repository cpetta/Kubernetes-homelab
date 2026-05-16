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
    alertmanager = {
      name         = "metrics-alertmanager"
      service_name = "kube-prometheus-stack-alertmanager"
      subnet       = "alertmanager"
      port         = 9093
    }
    prometheus = {
      name         = "metrics-prometheus"
      service_name = "kube-prometheus-stack-prometheus"
      subnet       = "prometheus"
      port         = 9090
    }
  }
  metrics_volumes = {
    grafana = {
      name     = "kube-prometheus-stack-grafana"
      size     = 20
      replicas = 1
    }
    prometheus = {
      name     = "kube-prometheus-stack-prometheus"
      size     = 20
      replicas = 1
    }
    thanos = {
      name     = "kube-prometheus-stack-thanos"
      size     = 20
      replicas = 1
    }
    alertmanager = {
      name     = "kube-prometheus-stack-alertmanager"
      size     = 20
      replicas = 1
    }
  }
}

resource "kubernetes_namespace_v1" "metrics" {
  metadata {
    name = "metrics"
    labels = {
      "pod-security.kubernetes.io/enforce" = "privileged"
    }
  }
}

resource "kubernetes_secret_v1" "grafana_admin" {
  metadata {
    name      = "grafana-admin-auth"
    namespace = kubernetes_namespace_v1.metrics.id
  }

  data = {
    username = "admin"
    password = var.grafana_password
  }

  type = "kubernetes.io/basic-auth"
}

#-------------------------------------------------------
# Metrics - Storage
#-------------------------------------------------------
resource "kubernetes_manifest" "metrics_longhorn_volume" {
  for_each   = { for i, v in local.metrics_volumes : i => v }
  depends_on = [helm_release.longhorn]
  manifest = {
    apiVersion = "longhorn.io/v1beta2"
    kind       = "Volume"

    metadata = {
      name      = each.value.name
      namespace = "longhorn-system"
      labels = {
        "app.kubernetes.io/name" = each.value.name
      }
    }

    spec = {
      size             = "${tostring(each.value.size * 1073741824)}" // size Gi in bytes
      numberOfReplicas = each.value.replicas
      frontend         = "blockdev"
      accessMode       = "rwo"
      dataLocality     = "disabled"
    }
  }
}

resource "kubernetes_persistent_volume_v1" "metrics" {
  depends_on = [kubernetes_manifest.metrics_longhorn_volume]
  for_each   = { for i, v in local.metrics_volumes : i => v }
  metadata {
    name = each.value.name
    labels = {
      "app.kubernetes.io/name" = each.value.name
    }
  }

  spec {
    storage_class_name = "longhorn"
    access_modes       = ["ReadWriteOnce"]

    capacity = {
      storage = "${each.value.size}Gi"
    }

    persistent_volume_source {
      csi {
        driver        = "driver.longhorn.io"
        volume_handle = kubernetes_manifest.metrics_longhorn_volume[each.key].manifest.metadata.name
      }
    }
  }
  lifecycle {
    ignore_changes = [
      metadata
    ]
  }
}

resource "kubernetes_persistent_volume_claim_v1" "metrics_grafana" {
  depends_on = [kubernetes_persistent_volume_v1.metrics]
  metadata {
    name      = "${local.metrics_volumes.grafana.name}-pvc"
    namespace = kubernetes_namespace_v1.metrics.id
  }
  spec {
    volume_name  = kubernetes_persistent_volume_v1.metrics["grafana"].metadata.0.name
    access_modes = ["ReadWriteOnce"]

    resources {
      requests = {
        storage = "${local.metrics_volumes.grafana.size}Gi"
      }
    }
  }
}

#-------------------------------------------------------
# Metrics - Helm & Config
#-------------------------------------------------------
resource "local_file" "metrics_values" {
  content  = templatefile("${path.module}/helm/templates/metrics.tftpl", {})
  filename = "${path.module}/helm/tmp/metrics.yml"
}

resource "helm_release" "kube_prometheus_stack" {
  name             = "kube-prometheus-stack"
  namespace        = kubernetes_namespace_v1.metrics.id
  create_namespace = false
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  version          = "85.0.3"
  take_ownership   = true

  values = [
    templatefile("${path.module}/helm/templates/metrics.tftpl", {})
  ]
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
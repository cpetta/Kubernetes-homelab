#-------------------------------------------------------
# Kubernetes - Metrics
#-------------------------------------------------------
locals {
  metrics_services = {
    grafana = {
      name           = "metrics-grafana"
      service_name   = "kube-prometheus-stack-grafana"
      subnet         = "grafana"
      port           = 80
      homepage_name  = "Dashboards"
      homepage_desc  = "Grafana"
      homepage_logo  = "grafana.png"
      homepage_group = "Apps"
      homepage_pod   = "app.kubernetes.io/name=grafana"
    }
  }
  metrics_volumes = {
    grafana = {
      name     = "kube-prometheus-stack-grafana"
      size     = 20
      replicas = 1
    }
    # prometheus = {
    #   name     = "kube-prometheus-stack-prometheus"
    #   size     = 20
    #   replicas = 1
    # }
    # thanos = {
    #   name     = "kube-prometheus-stack-thanos"
    #   size     = 20
    #   replicas = 1
    # }
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

# Fix for metrics scrapability
# https://github.com/siderolabs/talos/discussions/7214#discussioncomment-11709688
resource "kubernetes_secret_v1" "etcd_client_cert" {
  metadata {
    name      = "etcd-client-cert"
    namespace = kubernetes_namespace_v1.metrics.id
  }

  type = "Opaque"

  data = {
    "etcd-ca.crt"         = var.etcdCA_crt
    "etcd-client.crt"     = var.etcd_crt
    "etcd-client-key.key" = var.etcd_key
  }
}

#-------------------------------------------------------
# Metrics - Storage
#-------------------------------------------------------
resource "kubernetes_manifest" "metrics_longhorn_volume" {
  for_each   = { for i, v in local.metrics_volumes : i => v }
  depends_on = [argocd_application.longhorn]
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
resource "helm_release" "kube_prometheus_stack" {
  name             = "kube-prometheus-stack"
  namespace        = kubernetes_namespace_v1.metrics.id
  create_namespace = false
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  version          = "86.2.2"
  take_ownership   = true

  values = [
    templatefile("${path.module}/helm/templates/metrics.tftpl", {
      dns_zone = var.dns_zone,
      grafana_client_id = var.grafana_client_id,
      grafana_client_secret = var.grafana_client_secret,
    })
  ]
}

#-------------------------------------------------------
# Metrics - Grafana HTTP Route
#-------------------------------------------------------
resource "kubernetes_manifest" "Metrics_HTTP_Route" {
  for_each = { for i, v in local.metrics_services : i => v }
  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "HTTPRoute"
    metadata = {
      name      = each.value.name
      namespace = kubernetes_namespace_v1.metrics.id

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
          namespace = "traefik"
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
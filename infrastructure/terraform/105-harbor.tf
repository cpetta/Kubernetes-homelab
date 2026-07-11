#-------------------------------------------------------
# Harbor - Config
#-------------------------------------------------------
locals {
  harbor = {
    version = "1.19.1"
    subnet = "harbor"
    volumes = {
      registry = {
        volume_name = "harbor-registry"
        size = 5 // Gi
        replicas = 3
      }
      jobservice = {
        volume_name = "harbor-jobservice"
        size = 1 // Gi
        replicas = 3
      }
      trivy = {
        volume_name = "harbor-trivy"
        size = 1 // Gi
        replicas = 3
      }
    }
  }
}

#-------------------------------------------------------
# Harbor - Secrets
#-------------------------------------------------------
resource "kubernetes_secret_v1" "harbor_admin_password" {
  type = "Opaque"
  metadata {
    name      = "harbor-admin-password"
    namespace = "harbor"
  }
  data = {
    password = var.harbor_admin_password
  }
}

resource "kubernetes_secret_v1" "harbor_nginx" {
  type = "Opaque"
  metadata {
    name      = "harbor-nginx"
    namespace = "harbor"
  }
  data = {
    placeholder = ""
  }
}

#-------------------------------------------------------
# Harbor - Volumes
#-------------------------------------------------------
resource "kubernetes_manifest" "harbor_longhorn_volume" {
  depends_on = [argocd_application.longhorn]
  for_each   = { for i, v in local.harbor.volumes : i => v }
  manifest = {
    apiVersion = "longhorn.io/v1beta2"
    kind       = "Volume"

    metadata = {
      name      = each.value.volume_name
      namespace = "longhorn-system"
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

resource "kubernetes_persistent_volume_v1" "harbor" {
  depends_on = [kubernetes_manifest.harbor_longhorn_volume]
  for_each   = { for i, v in local.harbor.volumes : i => v }
  metadata {
    name = each.value.volume_name
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
        volume_handle = each.value.volume_name
      }
    }
  }
  lifecycle {
    ignore_changes = [
      metadata
    ]
  }
}

resource "kubernetes_persistent_volume_claim_v1" "harbor" {
  depends_on = [kubernetes_persistent_volume_v1.harbor]
  for_each   = { for i, v in local.harbor.volumes : i => v }
  metadata {
    name      = "harbor-${each.key}-pvc"
    namespace = "harbor"
  }
  spec {
    volume_name = each.value.volume_name
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "${each.value.size}Gi"
      }
    }
  }
}

#-------------------------------------------------------
# ArgoCD Helm Deployment
#-------------------------------------------------------
resource "argocd_application" "harbor" {
  metadata {
    name      = "harbor"
    namespace = kubernetes_namespace_v1.argo.id
  }

  spec {
    source {
      repo_url = "https://helm.goharbor.io"
      chart = "harbor"
      target_revision = local.harbor.version
      
      helm {
        release_name = "harbor"
        # TODO replace with GitOPs
        values = templatefile("${path.module}/helm/templates/harbor.tftpl", {
          subnet         = local.harbor.subnet,
          dns_zone       = var.dns_zone,
          pvc_registry   = "${local.harbor.volumes.registry.volume_name}-pvc"
          pvc_jobservice = "${local.harbor.volumes.jobservice.volume_name}-pvc"
          pvc_trivy      = "${local.harbor.volumes.trivy.volume_name}-pvc"
          db_password    = var.harbor_db_password
        }) 
      }
    }

    source {
      repo_url        = "git@git.${var.dns_zone}:chloe/homelab.git"
      target_revision = "HEAD"
      path            = "./applications/harbor"
      ref             = "config"
    }

    destination {
      server    = "https://kubernetes.default.svc"
      namespace = "harbor"
    }

    sync_policy {
      # automated {
      #   prune       = true
      #   self_heal   = true
      #   allow_empty = true
      # }
      sync_options = [
        "ServerSideApply=true",
        "Validate=false",
      ]
      
      retry {
        limit = "3"
        backoff {
          duration     = "30s"
          max_duration = "2m"
          factor       = "2"
        }
      }
    }
  }
}
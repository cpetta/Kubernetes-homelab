#-------------------------------------------------------
# ArgoCD
#-------------------------------------------------------
resource "kubernetes_namespace_v1" "argo" {
  metadata {
    name = "argocd"
    labels = {}
  }
}

#-------------------------------------------------------
# ArgoCD - DNS
#-------------------------------------------------------
resource "dns_a_record_set" "argocd" {
  zone     = "${var.dns_zone}."
  name     = "argocd"
  addresses = [
    var.k8_service_list.rp,
  ]
}

#-------------------------------------------------------
# ArgoCD - Forgejo Private Repo
#-------------------------------------------------------
resource "kubernetes_secret_v1" "argo_private_repo" {
  metadata {
    name      = "local-repo"
    namespace = kubernetes_namespace_v1.argo.id
    labels = {
      "argocd.argoproj.io/secret-type" = "repository"
    }
  }
  type = "Opaque"
  data = {
    type = "git"
    url = "git@git.${var.dns_zone}:chloe/homelab-applications.git"
    sshPrivateKey = file("../ssh/argocd_ed25519")
  }
}

#-------------------------------------------------------
# ArgoCD - Config
#-------------------------------------------------------
resource "local_file" "argo_cd_values" {
  content = templatefile("${path.module}/helm/templates/argocd.tftpl", {
    dns_zone = var.dns_zone,
    subnet = "argocd",
    server_replicas = 1,
    oidc_client_id = "argocd",
    oidc_client_secret = var.argocd_oidc_secret,
    sshFingerprint = var.forgejo_ssh_fingerprint,
    local_admin_email = var.local_admin_email,
  })
  filename = "${path.module}/helm/tmp/argo_cd.yaml"
}

#-------------------------------------------------------
# ArgoCD - Helm Initial install (cluster without argo)
# After install and running execute the following command
# terraform state rm helm_release.argocd
# then comment out the helm_release.argocd resource below
#-------------------------------------------------------
# resource "helm_release" "argocd" {
#   depends_on        = [
#   ]
#   name              = "argocd"
#   namespace         = kubernetes_namespace_v1.argo.id
#   create_namespace  = false
#   repository        = "https://argoproj.github.io/argo-helm"
#   chart             = "argo-cd"
#   version           = "10.1.2"

#   values = [
#     local_file.argo_cd_values.content
#   ]
# }

#-------------------------------------------------------
# Adopt into ArgoCD
#-------------------------------------------------------
resource "argocd_application" "argocd" {
  metadata {
    name      = "argocd"
    namespace = kubernetes_namespace_v1.argo.id
  }

  spec {
    source {
      repo_url = "https://argoproj.github.io/argo-helm"
      chart = "argo-cd"
      target_revision = "10.1.2"
      
      helm {
        release_name = "argocd"
        values = local_file.argo_cd_values.content # TODO replace with GitOPs
      }
    }
    
    destination {
      server    = "https://kubernetes.default.svc"
      namespace = kubernetes_namespace_v1.argo.id
    }

    sync_policy {
      automated {
        prune       = true
        self_heal   = true
        allow_empty = true
      }
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
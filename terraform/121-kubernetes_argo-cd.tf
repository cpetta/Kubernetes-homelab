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
# ArgoCD - Helm & Config
#-------------------------------------------------------
resource "local_file" "argo_cd_values" {
  content = templatefile("${path.module}/helm/templates/argocd.tftpl", {
    dns_zone = var.dns_zone,
    subnet = "argocd",
    server_replicas = 1,
    oidc_client_id = "argocd",
    oidc_client_secret = var.argocd_oidc_secret,
  })
  filename = "${path.module}/helm/tmp/argo_cd.yaml"
}

resource "helm_release" "argocd" {
  depends_on        = [
  ]
  name              = "argocd"
  namespace         = kubernetes_namespace_v1.argo.id
  create_namespace  = false
  repository        = "https://argoproj.github.io/argo-helm"
  chart             = "argo-cd"
  version           = "10.1.2"

  values = [
    local_file.argo_cd_values.content
  ]
}
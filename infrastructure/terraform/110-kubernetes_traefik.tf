#-------------------------------------------------------
# Kubernetes - Traefik
#-------------------------------------------------------
resource "kubernetes_namespace_v1" "traefik" {
  metadata {
    name = "traefik"
    labels = {
      "pod-security.kubernetes.io/enforce" = "privileged"
    }
  }
}

resource "helm_release" "traefik" {
  # depends_on = [kubernetes_persistent_volume_claim_v1.traefik_data]
  name              = "traefik"
  namespace         = kubernetes_namespace_v1.traefik.id
  create_namespace  = false
  dependency_update = true
  repository        = "https://traefik.github.io/charts"
  chart             = "traefik"
  version           = "41.0.0"
  values = [
    templatefile("${path.module}/helm/templates/traefik.tftpl", {
      dns_zone             = var.dns_zone,
      admin_email          = var.admin_email,
      password             = var.traefik_password,
      cloudflare_api_email = var.cloudflare_api_email,
      cloudflare_token     = var.cloudflare_token,
    })
  ]
}
#-------------------------------------------------------
# Kubernetes - MetalLB (ingress)
#-------------------------------------------------------
resource "kubernetes_namespace_v1" "metallb" {
  metadata {
    name = "metallb-system"
    labels = {
      "pod-security.kubernetes.io/enforce" = "privileged"
      "pod-security.kubernetes.io/audit"   = "privileged"
      "pod-security.kubernetes.io/warn"    = "privileged"
    }
  }
}

resource "local_file" "metallb_values" {
  content  = templatefile("${path.module}/helm/templates/metallb.tftpl", {})
  filename = "${path.module}/helm/tmp/metallb.yml"
}

resource "helm_release" "metallb" {
  name              = "metallb"
  namespace         = kubernetes_namespace_v1.metallb.id
  create_namespace  = false
  dependency_update = true
  repository        = "https://metallb.github.io/metallb"
  chart             = "metallb"

  # values = [
  #   local_file.metallb_values.content
  # ]
}

resource "terraform_data" "metallb_configs" {
  # count      = 0
  depends_on = [helm_release.metallb]
  input      = local_file.metallb_values.content
  provisioner "local-exec" {
    when        = destroy
    command     = "echo '${self.input}' | kubectl delete -f -"
    interpreter = ["/bin/bash", "-c"]
  }
}

# To comment out when setting count = 0 on terraform_data.metallb_configs
resource "terraform_data" "apply_metallb_configs" {
  depends_on = [terraform_data.metallb_configs]
  lifecycle {
    replace_triggered_by = [terraform_data.metallb_configs]
  }
  provisioner "local-exec" {
    command     = "echo '${terraform_data.metallb_configs.output}' | kubectl apply -f -"
    interpreter = ["/bin/bash", "-c"]
  }
}
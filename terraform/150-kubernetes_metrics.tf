#-------------------------------------------------------
# Kubernetes - Metrics
#-------------------------------------------------------
# resource "kubernetes_namespace_v1" "metrics" {
#   metadata {
#     name = "metrics"
#     labels = {
#       "pod-security.kubernetes.io/enforce" = "privileged"
#     }
#   }
# }

# resource "helm_release" "kube_prometheus_stack" {
#   name              = "kube-prometheus-stack"
#   namespace         = kubernetes_namespace_v1.metrics.id
#   dependency_update = true
#   repository        = "https://prometheus-community.github.io/helm-charts/"
#   chart             = "kube-prometheus-stack"
# }
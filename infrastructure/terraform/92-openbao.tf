resource "dns_a_record_set" "openbao" {
  zone     = "${var.dns_zone}."
  name     = "vault"
  addresses = [
    var.k8_service_list.rp,
  ]
}

resource "argocd_application" "openbao" {
  metadata {
    name      = "openbao"
    namespace = kubernetes_namespace_v1.argo.id
  }

  spec {
    source {
      repo_url = "https://openbao.github.io/openbao-helm"
      chart = "openbao"
      target_revision = "0.28.4"
      
      helm {
        release_name = "openbao"
        value_files = ["$config/applications/openbao/values.yaml"]
      }
    }

    source {
      repo_url        = "git@git.${var.dns_zone}:chloe/homelab.git"
      target_revision = "HEAD"
      path            = "./applications/openbao"
      ref             = "config"
    }

    destination {
      server    = "https://kubernetes.default.svc"
      namespace = "vault"
    }

    sync_policy {
      # automated {
      #   prune       = true
      #   self_heal   = true
      #   allow_empty = true
      # }
      sync_options = [
        "CreateNamespace=true",
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
    ignore_difference {
      group = "gateway.networking.k8s.io"
      kind  = "HTTPRoute"
      json_pointers = ["/spec/rules/0/backendRefs/0"]
    }
  }
}
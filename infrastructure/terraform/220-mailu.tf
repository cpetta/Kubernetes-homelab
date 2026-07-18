#-------------------------------------------------------
# mailu - DNS Records
#-------------------------------------------------------
resource "dns_a_record_set" "mailu_mail" {
  zone     = "${var.dns_zone}."
  name     = "mail"
  addresses = [
    var.k8_service_list.rp,
  ]
}

resource "dns_a_record_set" "mailu_smtp" {
  zone     = "${var.dns_zone}."
  name     = "smtp"
  addresses = [
    var.k8_service_list.rp,
  ]
}

resource "dns_a_record_set" "mailu_imap" {
  zone     = "${var.dns_zone}."
  name     = "imap"
  addresses = [
    var.k8_service_list.rp,
  ]
}

resource "dns_a_record_set" "mailu_pop3" {
  zone     = "${var.dns_zone}."
  name     = "pop3"
  addresses = [
    var.k8_service_list.rp,
  ]
}

resource "dns_mx_record_set" "mailu_smtp" {
  zone = "${var.dns_zone}."
  ttl  = 300

  mx {
    preference = 10
    exchange   = "smtp.${var.dns_zone}."
  }
}

# commented out due conflict with the A record
# resource "dns_ns_record_set" "mail" {
#   zone = "${var.dns_zone}."
#   name = "mail"
#   nameservers = [
#     "ns1.${var.dns_zone}.",
#     "ns2.${var.dns_zone}.",
#   ]
#   ttl = 300
# }

resource "argocd_application" "mailu" {
  metadata {
    name      = "mailu"
    namespace = kubernetes_namespace_v1.argo.id
  }

  spec {
    source {
      repo_url = "https://mailu.github.io/helm-charts/"
      chart = "mailu"
      target_revision = "2.7.1"
      
      helm {
        release_name = "mailu"
        value_files = ["$config/applications/mailu/values.yaml"]
      }
    }

    source {
      repo_url        = "git@git.${var.dns_zone}:chloe/homelab.git"
      target_revision = "HEAD"
      path            = "./applications/mailu"
      ref             = "config"
    }

    destination {
      server    = "https://kubernetes.default.svc"
      namespace = "mailu"
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
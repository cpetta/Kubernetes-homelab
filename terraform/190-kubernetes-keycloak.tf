#-------------------------------------------------------
# Kubernetes - KeyCloak
#-------------------------------------------------------
locals {
  keycloak_version = "26.6.1"
}

resource "kubernetes_namespace_v1" "keycloak" {
  metadata {
    name = "keycloak"
    labels = {}
  }
}

#-------------------------------------------------------
# KeyCloak - Secrets
#-------------------------------------------------------
resource "kubernetes_secret_v1" "keycloak_password" {
  metadata {
    name      = "keycloak-secrets"
    namespace = kubernetes_namespace_v1.keycloak.id
  }

  data = {
    db-user     = "keycloak_default"
    db-password = var.keycloak_db_password
    keycloak-password = var.keycloak_admin_password
  }

  type = "Opaque"
}

#-------------------------------------------------------
# Keycloak - Deployment
#-------------------------------------------------------
resource "kubernetes_stateful_set_v1" "keycloak" {
  depends_on = [helm_release.postgresql]
  metadata {
    name      = "keycloak"
    namespace = kubernetes_namespace_v1.keycloak.id

    labels = {
      app  = "keycloak"
    }
  }

  spec {
    replicas = 1
    service_name = "keycloak-discovery"
    
    selector {
      match_labels = {
        app  = "keycloak"
      }
    }
    
    template {
      metadata {
        labels = {
          app  = "keycloak"
        }
      }

      spec {
        container {
          name  = "keycloak"
          image = "quay.io/keycloak/keycloak:${local.keycloak_version}"

          args = [
            "start",
          ]

          port {
            name           = "http"
            container_port = 8080
            protocol       = "TCP"
          }
          port {
            name           = "jgroups"
            container_port = 7800
            protocol       = "TCP"
          }
          port {
            name           = "jgroups-fd"
            container_port = 57800
            protocol       = "TCP"
          }

          env {
            name  = "KC_BOOTSTRAP_ADMIN_USERNAME"
            value = "admin"
          }
          env {
            name  = "KC_BOOTSTRAP_ADMIN_PASSWORD"
            value = var.keycloak_admin_password
          }
          env {
            name = "KC_PROXY_HEADERS"
            value = "xforwarded"
          }
          env {
            name  = "KC_HTTP_ENABLED"
            value = "true"
          }
          env {
            name  = "KC_HOSTNAME_STRICT"
            value = "false"
          }
          env {
            name  = "KC_HEALTH_ENABLED"
            value = "true"
          }
          env {
            name  = "KC_CACHE"
            value = "ispn"
          }
          env {
            name  = "POD_IP"
            value_from {
              field_ref {
                field_path = "status.podIP"
              }
            }
          }
          env {
            name  = "KC_CACHE_EMBEDDED_NETWORK_BIND_ADDRESS"
            value = "$(POD_IP)"
          }
          env {
            name  = "KC_DB_URL_DATABASE"
            value = "keycloak"
          }
          env {
            name  = "KC_DB_URL_HOST"
            value = "postgresql.postgresql-database.svc.cluster.local"
          }
          env {
            name  = "KC_DB"
            value = "postgres"
          }
          env {
            name  = "KC_DB_USERNAME"
            value = "keycloak_default"
          }
          env {
            name  = "KC_DB_PASSWORD"
            value = var.keycloak_db_password
          }
          env {
            name  = "KC_HOSTNAME"
            value = "login.${var.dns_zone}"
          }

          env {
            name  = "KC_HOSTNAME_STRICT_HTTPS"
            value = "false"
          }
          env {
            name  = "KC_PROXY_ADDRESS_FORWARDING"
            value = "true"
          }
          env {
            name  = "KC_PROXY"
            value = "edge"
          }
          
          startup_probe {
            failure_threshold = 600
            http_get {
              path = "/health/started"
              port = 9000
            }
            period_seconds = 1
          }
          readiness_probe {
            http_get {
              path = "/health/ready"
              port = 9000
            }
            # initial_delay_seconds = 30
            period_seconds        = 10
          }
          liveness_probe {
            failure_threshold = 3
            http_get {
              path = "/health/live"
              port = 9000
            }
            # initial_delay_seconds = 30
            period_seconds        = 10
          }

          resources {
            requests = {
              cpu    = "500m"
              memory = "1700Mi"
            }
            limits = {
              cpu    = "2000m"
              memory = "2000Mi"
            }
          }
        }
      }
    }
  }
}

#-------------------------------------------------------
# Keycloak - Service
#-------------------------------------------------------
resource "kubernetes_service_v1" "keycloak_service" {
  metadata {
    name      = "keycloak"
    namespace = kubernetes_namespace_v1.keycloak.id
  }

  spec {
    selector = {
      app = "keycloak"
    }

    type = "ClusterIP"

    port {
      name        = "keycloak-tcp"
      port        = 8080
      protocol    = "TCP"
      target_port = 8080
    }
  }

  lifecycle {
    ignore_changes = [
      metadata
    ]
  }
}

resource "kubernetes_service_v1" "keycloak_discovery_service" {
  metadata {
    name      = "keycloak-discovery"
    namespace = kubernetes_namespace_v1.keycloak.id

    labels = {
      app = "keycloak"
    }
  }

  spec {
    selector = {
      app = "keycloak"
    }
    type = "ClusterIP"
    cluster_ip = "None"
  }

  lifecycle {
    ignore_changes = [
      metadata
    ]
  }
}

resource "kubernetes_manifest" "keycloak_HTTP_Route" {
  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "HTTPRoute"
    metadata = {
      name      = "keycloak"
      namespace = "traefik"
    }
    spec = {
      hostnames = [
        "login.${var.dns_zone}",
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
              name      = "keycloak"
              namespace = kubernetes_namespace_v1.keycloak.id
              port      = 8080
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

resource "kubernetes_manifest" "keycloak_Reference_Grant" {
  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1beta1"
    kind       = "ReferenceGrant"
    metadata = {
      name      = "keycloak"
      namespace = kubernetes_namespace_v1.keycloak.id
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
          name  = "keycloak"
        },
      ]
    }
  }
}
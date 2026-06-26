resource "harbor_config_auth" "oidc" {
  auth_mode                     = "oidc_auth"
  primary_auth_mode             = true
  oidc_name                     = "keycloak"
  oidc_endpoint                 = "https://login.${var.dns_zone}/realms/ChloesCorner"
  oidc_client_id                = "harbor"
  oidc_client_secret_wo         = var.harbor_oidc_client_secret
  oidc_client_secret_wo_version = 1
  oidc_scope                    = "openid,profile,roles,email"
  oidc_verify_cert              = true
  oidc_auto_onboard             = true
  oidc_user_claim               = "name"
  oidc_logout                   = true
  oidc_admin_group              = "harbor_administrators"
}

resource "harbor_config_security" "main" {
  cve_allowlist = [
    # "CVE-456", # Example
  ]
  # expires_at = "1701167767"
}

resource "harbor_config_system" "main" {
  project_creation_restriction = "adminonly"
  robot_token_expiration       = 30
  robot_name_prefix            = "robot@"
  storage_per_project          = 100
  notification_enable          = true
}

resource "harbor_garbage_collection" "main" {
  schedule        = "Daily"
  delete_untagged = true
  workers         = 1
}

resource "harbor_interrogation_services" "main" {
  default_scanner = "Trivy"
  vulnerability_scan_policy = "Daily"
}

#-------------------------------------------------------
# Harbor - Docker IO
#-------------------------------------------------------
resource "harbor_registry" "dockerio" {
  name          = "docker.io"
  provider_name = "docker-registry"
  endpoint_url  = "https://docker.io"
}

resource "harbor_project" "docker-io-proxy" {
  name          = "docker-io-proxy"
  registry_id = harbor_registry.dockerio.registry_id
  # deployment_security = "critical"
  public = true
}

#-------------------------------------------------------
# Harbor - Github
#-------------------------------------------------------
resource "harbor_registry" "ghcr" {
  name          = "ghcr.io"
  provider_name = "github"
  endpoint_url  = "https://ghcr.io"
}

resource "harbor_project" "ghcr-proxy" {
  name          = "ghcr.io-proxy"
  registry_id = harbor_registry.ghcr.registry_id
  # deployment_security = "critical"
  public = true
}

#-------------------------------------------------------
# Harbor - Google
#-------------------------------------------------------
resource "harbor_registry" "gcr" {
  name          = "gcr.io"
  provider_name = "docker-registry"
  endpoint_url  = "https://gcr.io"
}

resource "harbor_project" "gcr-proxy" {
  name          = "gcr.io-proxy"
  registry_id = harbor_registry.gcr.registry_id
  # deployment_security = "critical"
  public = true
}

#-------------------------------------------------------
# Harbor - K8s
#-------------------------------------------------------
resource "harbor_registry" "k8s" {
  name          = "registry.k8s.io"
  provider_name = "docker-registry"
  endpoint_url  = "https://registry.k8s.io"
}

resource "harbor_project" "k8s-proxy" {
  name          = "registry.k8s.io-proxy"
  registry_id = harbor_registry.k8s.registry_id
  # deployment_security = "critical"
  public = true
}

#-------------------------------------------------------
# Harbor - Red Hat Quay
#-------------------------------------------------------
resource "harbor_registry" "quay" {
  name          = "quay.io"
  provider_name = "docker-registry"
  endpoint_url  = "https://quay.io"
}

resource "harbor_project" "quay-proxy" {
  name        = "quay.io-proxy"
  registry_id = harbor_registry.quay.registry_id
  # deployment_security = "critical"
  public = true
}

#-------------------------------------------------------
# Harbor - Docker Hub
#-------------------------------------------------------
resource "harbor_registry" "docker" {
  name          = "docker-hub"
  provider_name = "docker-hub"
  endpoint_url  = "https://hub.docker.com"
}

resource "harbor_project" "docker-proxy" {
  name          = "docker-hub-proxy"
  registry_id = harbor_registry.docker.registry_id
  # deployment_security = "critical"
  public = true
}

#-------------------------------------------------------
# Harbor - Forgejo
#-------------------------------------------------------
resource "harbor_registry" "forgejo" {
  name          = "forgejo"
  provider_name = "docker-registry"
  endpoint_url  = "https://code.forgejo.org"
}

resource "harbor_project" "forgejo-proxy" {
  name          = "forgejo-proxy"
  registry_id = harbor_registry.forgejo.registry_id
  # deployment_security = "critical"
  public = true
}

#-------------------------------------------------------
# Harbor - registry-1.docker.io
#-------------------------------------------------------
resource "harbor_registry" "dockerio1" {
  name          = "registry-1.docker.io"
  provider_name = "docker-registry"
  endpoint_url  = "https://registry-1.docker.io"
}

resource "harbor_project" "dockerio1-proxy" {
  name          = "registry-1.docker.io-proxy"
  registry_id = harbor_registry.forgejo.registry_id
  # deployment_security = "critical"
  public = true
}
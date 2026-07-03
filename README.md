# Kubernetes Homelab

## High Level Goals and Considerations

### Reliability
- high-availability
- load balancing
- automatic restarts

### Observability
- Alerts
- Metrics
- Logs

### Security
## Economic
## Efficiency


## What’s running
### Core Software
- Talos Linux
- Technitium DNS Server (dns caching, ad-blocking, service discovery)
- MetalLB (IP address assignment)
- Longhorn (storage provider)
- Backblaze B2 (S3-compatible storage for backups)
- Harbor (container registry/proxy)
- Traefik (reverse proxy)
- Cert-Manager (automatic TLS certificates)
- Postgress (RDBMS)
- Redis (caching database)
- Keycloak (authentication and single-sign-on)
- Mailu (local email server)

### User Applications
- Jellyfin (local media server)
- Kiwix (wikipedia, stack overflow, and documentation library server)
- Forgejo (GIT code repository - Github alternative)
- Nextcloud (local cloud file storage)
- Grafana (metrics, monitoring and observability)
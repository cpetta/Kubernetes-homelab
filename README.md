# Kubernetes Homelab

## Goals and Considerations
- [Reliability](#Reliability)
- [Observability](#Observability)
- [Security](#Security)
- [Economic](#Economic)
- [Efficiency](#Efficiency)

## Reliability
- high-availability
- load balancing
- automatic restarts

## Observability
- Alerts
- Metrics
- Logs


## Security

#### Talos linux
Talos was chosen for several reasons, first, it's security hardened by default, No SSH, No shell, No package manager. Immutable OS, which reduces malware ability to gain a persistent foothold. Additionally, it can be managed via terraform, which allows for declarative and auditable upgrade cycles.

#### Keycloak
I chose to setup Keycloak in order to centralize identity and access management, this reduces complexity by eliminating the need for different usernames and passwords for every app, and allows me to eliminate potential security flaws in the login flow for individual apps. Additionally, this allows me to setup Multi-factor authentication with TOTP and hardware keys, even when those security measures haven't been implemented in an app.

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

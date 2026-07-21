# Kubernetes Homelab

## Goals and Considerations
- [Reliability](#Reliability)
- [Observability](#Observability)
- [Security](#Security)
- [Economic](#Economic)
- [Efficiency](#Efficiency)

## Reliability
- Infrastructure as code
For this project, it is important that any and all configuration happen in a reproducible way. During past server projects, it’s been difficult to maintain systems long term due to configuration drift over time. When updating or changing configuration, it was often difficult to remember what steps were taken to resolve an issue. Using an infrastructure as code approach as greatly alleviated that issue by keeping an accurate record of the desired state, and applying it consistently.

- high-availability
Achieved using Kubernetes, automatic restarts or HA where available.

## Observability
- Alerts/Metrics
Alert manager was installed as part of kube-prometheus-stack, and is currently my goto for catching potential issues before they become a problem. Prometheus provides insight into most services and metrics without needing to dig into logs.

## Security
#### Talos linux
Talos was chosen for several reasons, first, it's security hardened by default, no SSH, no shell, no package manager and has an immutable OS, which reduces malware ability to gain a persistent foothold. It can also be managed with terraform, which allows for declarative and auditable upgrade cycles.

Additional Talos security measures we're using
- Secure boot with TPM

#### Keycloak
I chose to setup Keycloak in order to centralize identity and access management, this reduces complexity by eliminating the need for different usernames and passwords for every app, and allows me to eliminate potential security flaws in the login flow for individual apps. Additionally, this allows me to setup Multi-factor authentication with TOTP and hardware keys, even when those security measures haven't been implemented in an app.

#### OpenBao
OpenBao is an opensource fork of Hashicorp vault. I chose to set this up to align with best-practices for secret storage. Previously, secrets were stored in a terraform vars file that wasn’t uploaded to git. This made working remotely difficult. OpenBao solves this by centralizing secret management and storage in-cluster.

## Economic/Efficiency
At time of writing (2026) RAM and SSD pricing is 3 to 4 times more expensive than it was a year ago. As a result, I've opted to use old, refurbished computers from a local computer recycler. A benefit of using mini pcs is that they are often highly energy efficient. The 6 mini PC’s on average use about 60w, which equates to $9 a month or $108 a year.

## What’s running
### Core Software
- Talos Linux
- Technitium DNS Server (dns caching, ad-blocking, service discovery)
- MetalLB (IP address assignment)
- Longhorn (storage provider)
- ArgoCD (GitOps continuous delivery)
- OpenBao (Hashicorp vault fork for centralized management and storage of secrets)
- External Secrets Operator (Secret manager that integrates OpenBao with Kubernetes)
- Backblaze B2 (S3-compatible storage for backups)
- Harbor (container registry/proxy)
- Harbor Trivy Scanner (Vulnerability scans for container images)
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

### Planned future deployments
- [ ] Woodpecker CI
- [ ] VaultWarden
- [ ] Falco
- [ ] Crowdsec
- [ ] OpenProject
- [ ] RustDesk
- [ ] PenPot
- [ ] Matrix Chat
- [ ] OpenCost
- [ ] Zammand
- [ ] Immich
- [ ] n8n

### Planned migrations
- [ ] Postgress → CloudNativePG
- [ ] Keycloak → Keycloak Terraform provider for client management
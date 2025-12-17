# Nornos Infrastructure

Production-ready Infrastructure as Code (IaC) for the Nornos Health Platform.

## Overview

Nornos is a privacy-first health analytics platform that enables:
- **Patients** to securely store and control their health data
- **Doctors** to access patient data with explicit consent
- **AI Agents** to provide personalized health recommendations

## Architecture

```
                                    ┌─────────────────────────────────────────┐
                                    │           CDN / Edge (Cloudflare)       │
                                    └─────────────────┬───────────────────────┘
                                                      │
                    ┌─────────────────────────────────┼─────────────────────────────────┐
                    │                                 │                                 │
                    ▼                                 ▼                                 ▼
        ┌───────────────────┐           ┌───────────────────┐           ┌───────────────────┐
        │   Patient App     │           │   Doctor App      │           │   Admin Dashboard │
        │   (Next.js PWA)   │           │   (Next.js SPA)   │           │   (Internal)      │
        └─────────┬─────────┘           └─────────┬─────────┘           └─────────┬─────────┘
                  │                               │                               │
                  └───────────────┬───────────────┴───────────────────────────────┘
                                  │
                                  ▼
                    ┌─────────────────────────────────┐
                    │      API Gateway (Kong/Traefik) │
                    │      - Rate Limiting            │
                    │      - Authentication           │
                    │      - Request Routing          │
                    └─────────────────┬───────────────┘
                                      │
        ┌─────────────────────────────┼─────────────────────────────────┐
        │                             │                                 │
        ▼                             ▼                                 ▼
┌───────────────┐         ┌───────────────────┐             ┌───────────────────┐
│ Auth Service  │         │   Relay Server    │             │  Agent Service    │
│ - JWT/OAuth   │         │   - Consent Mgmt  │             │  - Meta Agents    │
│ - MFA         │         │   - Data Sharing  │             │  - Specialist     │
│ - Sessions    │         │   - Audit Logs    │             │  - LLM Integration│
└───────┬───────┘         └─────────┬─────────┘             └─────────┬─────────┘
        │                           │                                 │
        │                           ▼                                 │
        │               ┌───────────────────┐                         │
        │               │ Shared Data Server│                         │
        │               │ - Patient Profiles│                         │
        │               │ - Health Records  │                         │
        │               └─────────┬─────────┘                         │
        │                         │                                   │
        └─────────────────────────┼───────────────────────────────────┘
                                  │
                    ┌─────────────┼─────────────┐
                    │             │             │
                    ▼             ▼             ▼
            ┌───────────┐ ┌───────────┐ ┌───────────┐
            │PostgreSQL │ │   Redis   │ │   MinIO   │
            │ (Primary) │ │  (Cache)  │ │ (Objects) │
            └───────────┘ └───────────┘ └───────────┘
```

## Repository Structure

```
nornos-infrastructure/
├── docs/                    # Documentation
│   ├── adr/                 # Architecture Decision Records
│   ├── ARCHITECTURE.md      # Detailed architecture
│   ├── SECURITY.md          # Security model
│   └── RUNBOOK.md           # Operations guide
│
├── terraform/               # Cloud Infrastructure (AWS)
│   ├── environments/        # Environment-specific configs
│   │   ├── dev/
│   │   ├── staging/
│   │   └── production/
│   └── modules/             # Reusable modules
│       ├── kubernetes/      # EKS cluster
│       ├── database/        # RDS PostgreSQL
│       ├── networking/      # VPC, subnets
│       └── security/        # IAM, KMS
│
├── kubernetes/              # Kubernetes Manifests
│   ├── base/                # Kustomize base configs
│   └── overlays/            # Environment overlays
│
├── helm/                    # Helm Charts
│   └── nornos/
│
├── .github/workflows/       # CI/CD Pipelines
│
├── scripts/                 # Utility scripts
│
└── docker/                  # Dockerfile templates
```

## Quick Start

### Prerequisites

- AWS CLI configured
- Terraform >= 1.5
- kubectl >= 1.28
- Helm >= 3.12
- Docker >= 24.0

### 1. Deploy Infrastructure (Terraform)

```bash
cd terraform/environments/dev
terraform init
terraform plan
terraform apply
```

### 2. Deploy Applications (Kubernetes)

```bash
# Configure kubectl
aws eks update-kubeconfig --name nornos-dev --region eu-central-1

# Deploy with Kustomize
kubectl apply -k kubernetes/overlays/dev
```

### 3. Deploy with Helm (Alternative)

```bash
helm install nornos ./helm/nornos -f helm/nornos/values-dev.yaml
```

## Environments

| Environment | Purpose | AWS Account | Domain |
|-------------|---------|-------------|--------|
| **dev** | Development & Testing | nornos-dev | *.dev.nornos.io |
| **staging** | Pre-production | nornos-staging | *.staging.nornos.io |
| **production** | Live system | nornos-prod | *.nornos.io |

## Security

- All data encrypted at rest (AES-256)
- TLS 1.3 for all communications
- GDPR & HIPAA compliant data handling
- Consent-based data access model
- Audit logging for all data access

See [SECURITY.md](docs/SECURITY.md) for details.

## Contributing

1. Create a feature branch
2. Make changes
3. Run `terraform fmt` and `terraform validate`
4. Create a Pull Request
5. Wait for CI checks and review

## License

Proprietary - Nornos Health GmbH

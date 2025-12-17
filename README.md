# Nornos Infrastructure

Production-ready Infrastructure as Code (IaC) for the Nornos Health Platform on **Hetzner Cloud**.

## Why Hetzner Cloud?

| Aspect | Hetzner | AWS |
|--------|---------|-----|
| **Cost** | ~€56/month (dev) | ~$200/month |
| **Data Sovereignty** | German company, EU data centers | US company |
| **GDPR** | Native compliance | Requires configuration |
| **Simplicity** | Straightforward pricing | Complex pricing |
| **Performance** | Excellent | Excellent |

## Architecture

```
                                    ┌─────────────────────────────────────────┐
                                    │         Hetzner Load Balancer           │
                                    │         (€5.39/month)                   │
                                    └─────────────────┬───────────────────────┘
                                                      │
                    ┌─────────────────────────────────┼─────────────────────────────────┐
                    │                                 │                                 │
                    ▼                                 ▼                                 ▼
        ┌───────────────────┐           ┌───────────────────┐           ┌───────────────────┐
        │   Patient App     │           │   Doctor App      │           │   Agent Service   │
        │   (k3s Pod)       │           │   (k3s Pod)       │           │   (k3s Pod)       │
        └───────────────────┘           └───────────────────┘           └───────────────────┘
                                                  │
                    ┌─────────────────────────────┼─────────────────────────────────┐
                    │                             │                                 │
                    ▼                             ▼                                 ▼
        ┌───────────────────┐           ┌───────────────────┐           ┌───────────────────┐
        │   Relay Server    │           │ Shared Data Server│           │   Auth Service    │
        │   (k3s Pod)       │           │   (k3s Pod)       │           │   (k3s Pod)       │
        └───────────────────┘           └───────────────────┘           └───────────────────┘
                    │                             │                                 │
                    └─────────────────────────────┼─────────────────────────────────┘
                                                  │
                    ┌─────────────────────────────┼─────────────────────────────────┐
                    │                             │                                 │
                    ▼                             ▼                                 ▼
        ┌───────────────────┐           ┌───────────────────┐           ┌───────────────────┐
        │   PostgreSQL      │           │      Redis        │           │  Hetzner Object   │
        │   (Dedicated VM)  │           │  (Dedicated VM)   │           │  Storage (S3)     │
        └───────────────────┘           └───────────────────┘           └───────────────────┘
```

## Repository Structure

```
nornos-infrastructure/
├── docs/
│   ├── adr/                 # Architecture Decision Records
│   │   ├── 001-data-sovereignty.md
│   │   ├── 002-consent-model.md
│   │   └── 003-agent-architecture.md
│   ├── ARCHITECTURE.md
│   └── SECURITY.md
│
├── terraform/
│   ├── environments/
│   │   ├── dev/             # Dev: ~€56/month
│   │   ├── staging/
│   │   └── production/      # Prod: ~€260/month
│   └── modules/
│       ├── networking/      # VPC, Subnets, Firewalls
│       ├── kubernetes/      # k3s Cluster
│       └── database/        # PostgreSQL, Redis
│
├── kubernetes/
│   ├── base/                # Base manifests
│   └── overlays/            # Environment overlays
│
└── .github/workflows/       # CI/CD
```

## Cost Comparison

### Development Environment (~€56/month)

| Resource | Type | Monthly Cost |
|----------|------|--------------|
| Control Plane | CX21 (2 vCPU, 4GB) | €4.51 |
| Workers (2x) | CX31 (2 vCPU, 8GB) | €17.96 |
| Agent Worker | CX41 (4 vCPU, 16GB) | €17.85 |
| PostgreSQL | CX21 + 50GB Volume | €6.81 |
| Redis | CX11 (1 vCPU, 2GB) | €3.29 |
| Load Balancer | LB11 | €5.39 |
| **Total** | | **~€56/month** |

### Production Environment (~€260/month)

| Resource | Type | Monthly Cost |
|----------|------|--------------|
| Control Plane (3x) | CX31 (2 vCPU, 8GB) | €26.94 |
| Workers (4x) | CX41 (4 vCPU, 16GB) | €71.40 |
| Agent Workers (3x) | CX51 (8 vCPU, 32GB) | €106.74 |
| PostgreSQL | CX41 + 500GB Volume | €40.85 |
| Redis | CX31 | €8.98 |
| Load Balancer | LB11 | €5.39 |
| **Total** | | **~€260/month** |

## Quick Start

### Prerequisites

- [Hetzner Cloud Account](https://www.hetzner.com/cloud)
- [Terraform](https://www.terraform.io/downloads) >= 1.5
- [kubectl](https://kubernetes.io/docs/tasks/tools/) >= 1.28
- [Helm](https://helm.sh/docs/intro/install/) >= 3.12

### 1. Get Hetzner API Token

1. Go to [Hetzner Cloud Console](https://console.hetzner.cloud/)
2. Create a new project or select existing
3. Go to Security → API Tokens → Generate API Token
4. Copy the token (Read & Write permissions)

### 2. Deploy Infrastructure

```bash
cd terraform/environments/dev

# Initialize Terraform
terraform init

# Create terraform.tfvars
cat > terraform.tfvars <<EOF
hcloud_token   = "your-hetzner-api-token"
ssh_public_key = "ssh-ed25519 AAAA... your-email@example.com"
EOF

# Preview changes
terraform plan

# Deploy
terraform apply
```

### 3. Configure kubectl

```bash
# Get kubeconfig from control plane
scp root@<CONTROL_PLANE_IP>:/etc/rancher/k3s/k3s.yaml ./kubeconfig

# Update server address
sed -i 's/127.0.0.1/<CONTROL_PLANE_IP>/g' ./kubeconfig

# Set KUBECONFIG
export KUBECONFIG=$(pwd)/kubeconfig

# Verify
kubectl get nodes
```

### 4. Deploy Applications

```bash
# Deploy to dev environment
kubectl apply -k kubernetes/overlays/dev

# Verify
kubectl get pods -n nornos
kubectl get services -n nornos
```

## Hetzner Locations

| Location | Code | Region | Latency (Germany) |
|----------|------|--------|-------------------|
| Falkenstein | fsn1 | Germany | <5ms |
| Nuremberg | nbg1 | Germany | <5ms |
| Helsinki | hel1 | Finland | ~30ms |
| Ashburn | ash | USA | ~90ms |

**Recommendation**: Use `fsn1` for EU deployments (cheapest, lowest latency).

## Security

- All servers in private network (10.0.0.0/16)
- Only Load Balancer exposed to internet
- PostgreSQL and Redis only accessible from Kubernetes nodes
- SSH access restricted (configurable in firewall)
- TLS termination at ingress controller

## GitHub Secrets Required

| Secret | Description |
|--------|-------------|
| `HCLOUD_TOKEN` | Hetzner Cloud API token |
| `SSH_PUBLIC_KEY` | SSH public key for server access |
| `KUBECONFIG` | Base64-encoded kubeconfig |
| `NORNOS_REPO_TOKEN` | GitHub PAT for nornos repo access |
| `SLACK_WEBHOOK_URL` | (Optional) Slack notifications |

## Monitoring

Deploy Prometheus + Grafana stack:

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install monitoring prometheus-community/kube-prometheus-stack -n monitoring --create-namespace
```

## Backup Strategy

### PostgreSQL

```bash
# Automated daily backups via cron on database server
0 3 * * * pg_dump -U nornos_admin nornos | gzip > /mnt/postgres-data/backups/nornos-$(date +\%Y\%m\%d).sql.gz

# Keep last 7 days
find /mnt/postgres-data/backups -mtime +7 -delete
```

### Hetzner Snapshots

```bash
# Create server snapshot
hcloud server create-image --type snapshot nornos-dev-postgres

# Create volume snapshot
hcloud volume create-from-snapshot --source-snapshot <id>
```

## License

Proprietary - Nornos Health GmbH

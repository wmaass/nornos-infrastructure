# Nornos Single-VM Deployment

Deploy the complete Nornos platform on a single server using Docker Compose.

## Requirements

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| **CPU** | 4 vCPU | 8 vCPU |
| **RAM** | 16 GB | 32 GB |
| **Storage** | 100 GB SSD | 200 GB SSD |
| **OS** | Ubuntu 22.04 | Ubuntu 22.04/24.04 |
| **Network** | Public IP | Public IP |

### Hetzner Recommendations

| Environment | Server Type | Price |
|-------------|-------------|-------|
| **Dev/Test** | CX41 (4 vCPU, 16GB) | €17.85/month |
| **Production** | CX51 (8 vCPU, 32GB) | €35.58/month |
| **High Load** | CCX33 (8 vCPU, 32GB Dedicated) | €89/month |

## Quick Start

### 1. SSH into your server

```bash
ssh root@your-server-ip
```

### 2. Clone and run setup

```bash
# Clone repository
git clone https://github.com/wmaass/nornos-infrastructure.git
cd nornos-infrastructure/docker/single-vm

# Run setup script
chmod +x setup.sh
sudo ./setup.sh
```

### 3. Configure environment

```bash
cd /opt/nornos
nano .env
```

Edit these values:
```env
DOMAIN=nornos.yourdomain.com
ACME_EMAIL=your@email.com
OPENAI_API_KEY=sk-...
```

### 4. Configure DNS

Point these subdomains to your server IP:

| Subdomain | Purpose |
|-----------|---------|
| `patient.yourdomain.com` | Patient App |
| `doctor.yourdomain.com` | Doctor App |
| `api.yourdomain.com` | Shared Data API |
| `relay.yourdomain.com` | Relay Server |
| `auth.yourdomain.com` | Auth Service |
| `agents.yourdomain.com` | Agent Service |
| `vault.yourdomain.com` | Vault Server |

### 5. Start services

```bash
cd /opt/nornos
docker compose up -d
```

### 6. Verify

```bash
# Check all containers are running
docker compose ps

# Check logs
docker compose logs -f

# Test endpoints
curl -I https://patient.yourdomain.com
curl -I https://doctor.yourdomain.com
```

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         Internet                                │
└─────────────────────────────┬───────────────────────────────────┘
                              │ :80, :443
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                        Traefik                                  │
│              (Reverse Proxy + SSL Termination)                  │
└─────────────────────────────┬───────────────────────────────────┘
                              │
        ┌─────────────────────┼─────────────────────┐
        │                     │                     │
        ▼                     ▼                     ▼
┌───────────────┐    ┌───────────────┐    ┌───────────────┐
│  Patient App  │    │  Doctor App   │    │ Agent Service │
│    :3004      │    │    :3002      │    │    :8000      │
└───────────────┘    └───────────────┘    └───────────────┘
        │                     │                     │
        └─────────────────────┼─────────────────────┘
                              │
        ┌─────────────────────┼─────────────────────┐
        │                     │                     │
        ▼                     ▼                     ▼
┌───────────────┐    ┌───────────────┐    ┌───────────────┐
│ Relay Server  │    │Shared Data   │    │ Auth Service  │
│    :8001      │    │    :3003      │    │    :3001      │
└───────────────┘    └───────────────┘    └───────────────┘
        │                     │                     │
        └─────────────────────┼─────────────────────┘
                              │
                ┌─────────────┼─────────────┐
                │             │             │
                ▼             ▼             ▼
        ┌───────────┐ ┌───────────┐ ┌───────────┐
        │PostgreSQL │ │   Redis   │ │   Vault   │
        │   :5432   │ │   :6379   │ │   :3006   │
        └───────────┘ └───────────┘ └───────────┘
```

## Commands

### Start all services
```bash
docker compose up -d
```

### Stop all services
```bash
docker compose down
```

### View logs
```bash
# All services
docker compose logs -f

# Specific service
docker compose logs -f agent-service
```

### Update to new version
```bash
# Pull latest images
docker compose pull

# Restart with new images
docker compose up -d
```

### Backup database
```bash
docker exec nornos-postgres pg_dump -U nornos nornos > backup-$(date +%Y%m%d).sql
```

### Restore database
```bash
cat backup.sql | docker exec -i nornos-postgres psql -U nornos nornos
```

## SSL Certificates

SSL certificates are automatically obtained from Let's Encrypt via Traefik.

- Certificates are stored in Docker volume `traefik-letsencrypt`
- Auto-renewed before expiration
- No manual intervention needed

## Monitoring

### Basic health checks

```bash
# Check all containers
docker compose ps

# Check container resource usage
docker stats
```

### Add Prometheus + Grafana (optional)

```bash
# Add to docker-compose.yml or run separately
docker run -d \
  --name prometheus \
  --network nornos-backend \
  -p 9090:9090 \
  prom/prometheus

docker run -d \
  --name grafana \
  --network nornos-frontend \
  -p 3000:3000 \
  grafana/grafana
```

## Troubleshooting

### Containers not starting

```bash
# Check logs
docker compose logs traefik
docker compose logs postgres

# Check if ports are in use
netstat -tulpn | grep -E ':(80|443|5432)'
```

### SSL certificate issues

```bash
# Check Traefik logs
docker compose logs traefik | grep -i acme

# Ensure DNS is pointing to server
dig patient.yourdomain.com
```

### Database connection issues

```bash
# Test database connection
docker exec -it nornos-postgres psql -U nornos -d nornos -c "SELECT 1"

# Check network
docker network inspect nornos-backend
```

## Security Checklist

- [ ] Changed all default passwords in `.env`
- [ ] Set up firewall (UFW): `ufw allow 80,443/tcp && ufw enable`
- [ ] Configured fail2ban for SSH
- [ ] Set up automated backups
- [ ] Monitoring alerts configured
- [ ] Regular security updates: `apt update && apt upgrade`

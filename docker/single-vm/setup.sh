#!/bin/bash
# Nornos Single-VM Setup Script
# Tested on Ubuntu 22.04 LTS

set -e

echo "=========================================="
echo "  Nornos Production Setup"
echo "=========================================="

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root (sudo ./setup.sh)"
  exit 1
fi

# Update system
echo "[1/6] Updating system..."
apt update && apt upgrade -y

# Install Docker
echo "[2/6] Installing Docker..."
if ! command -v docker &> /dev/null; then
  curl -fsSL https://get.docker.com | sh
  systemctl enable docker
  systemctl start docker
else
  echo "Docker already installed"
fi

# Install Docker Compose
echo "[3/6] Installing Docker Compose..."
if ! command -v docker-compose &> /dev/null; then
  apt install -y docker-compose-plugin
else
  echo "Docker Compose already installed"
fi

# Create nornos user
echo "[4/6] Creating nornos user..."
if ! id "nornos" &>/dev/null; then
  useradd -m -s /bin/bash nornos
  usermod -aG docker nornos
else
  echo "User nornos already exists"
fi

# Create directory structure
echo "[5/6] Creating directories..."
mkdir -p /opt/nornos
chown nornos:nornos /opt/nornos

# Copy files
echo "[6/6] Setting up configuration..."
cp docker-compose.yml /opt/nornos/
cp env.example /opt/nornos/.env.example

# Generate secrets
echo ""
echo "=========================================="
echo "  Generating secure passwords..."
echo "=========================================="

POSTGRES_PW=$(openssl rand -base64 32)
REDIS_PW=$(openssl rand -base64 32)
JWT_SECRET=$(openssl rand -base64 64)

echo "POSTGRES_PASSWORD: $POSTGRES_PW"
echo "REDIS_PASSWORD: $REDIS_PW"
echo "JWT_SECRET: $JWT_SECRET"

# Create .env file
cat > /opt/nornos/.env << EOF
# Generated on $(date)

# DOMAIN - CHANGE THIS!
DOMAIN=nornos.example.com
ACME_EMAIL=admin@example.com

# Database
POSTGRES_DB=nornos
POSTGRES_USER=nornos
POSTGRES_PASSWORD=$POSTGRES_PW
REDIS_PASSWORD=$REDIS_PW

# Security
JWT_SECRET=$JWT_SECRET
TRAEFIK_AUTH=

# Docker Registry
GITHUB_USER=wmaass
VERSION=latest

# AI Keys - ADD YOUR KEYS!
OPENAI_API_KEY=
ANTHROPIC_API_KEY=
EOF

chown nornos:nornos /opt/nornos/.env
chmod 600 /opt/nornos/.env

echo ""
echo "=========================================="
echo "  Setup Complete!"
echo "=========================================="
echo ""
echo "Next steps:"
echo ""
echo "1. Edit /opt/nornos/.env and set:"
echo "   - DOMAIN (your domain)"
echo "   - ACME_EMAIL (your email)"
echo "   - OPENAI_API_KEY / ANTHROPIC_API_KEY"
echo ""
echo "2. Configure DNS:"
echo "   - patient.yourdomain.com → $(curl -s ifconfig.me)"
echo "   - doctor.yourdomain.com  → $(curl -s ifconfig.me)"
echo "   - api.yourdomain.com     → $(curl -s ifconfig.me)"
echo "   - relay.yourdomain.com   → $(curl -s ifconfig.me)"
echo "   - auth.yourdomain.com    → $(curl -s ifconfig.me)"
echo "   - agents.yourdomain.com  → $(curl -s ifconfig.me)"
echo "   - vault.yourdomain.com   → $(curl -s ifconfig.me)"
echo ""
echo "3. Start Nornos:"
echo "   cd /opt/nornos"
echo "   docker compose up -d"
echo ""
echo "4. Check status:"
echo "   docker compose ps"
echo "   docker compose logs -f"
echo ""

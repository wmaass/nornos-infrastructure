# Nornos Database Module - Hetzner Cloud
# Deploys PostgreSQL and Redis on dedicated servers

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.45"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

# Variables
variable "environment" {
  description = "Environment name"
  type        = string
}

variable "network_id" {
  description = "Hetzner network ID"
  type        = number
}

variable "database_subnet_id" {
  description = "Database subnet ID"
  type        = string
}

variable "firewall_id" {
  description = "Firewall ID for database servers"
  type        = number
}

variable "ssh_key_id" {
  description = "SSH key ID"
  type        = number
}

variable "location" {
  description = "Hetzner Cloud location"
  type        = string
  default     = "fsn1"
}

variable "postgres_server_type" {
  description = "Server type for PostgreSQL"
  type        = string
  default     = "cx31" # 2 vCPU, 8GB RAM
}

variable "redis_server_type" {
  description = "Server type for Redis"
  type        = string
  default     = "cx21" # 2 vCPU, 4GB RAM
}

variable "postgres_volume_size" {
  description = "Volume size for PostgreSQL data (GB)"
  type        = number
  default     = 100
}

variable "tags" {
  description = "Common tags"
  type        = map(string)
  default     = {}
}

# Locals
locals {
  name_prefix = "nornos-${var.environment}"
  
  common_labels = merge(var.tags, {
    environment = var.environment
    managed_by  = "terraform"
    project     = "nornos"
  })
}

# Generate PostgreSQL password
resource "random_password" "postgres" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# Generate Redis password
resource "random_password" "redis" {
  length  = 32
  special = false
}

# PostgreSQL Volume for data persistence
resource "hcloud_volume" "postgres" {
  name     = "${local.name_prefix}-postgres-data"
  size     = var.postgres_volume_size
  location = var.location
  format   = "ext4"

  labels = merge(local.common_labels, {
    service = "postgresql"
  })
}

# PostgreSQL Server
resource "hcloud_server" "postgres" {
  name        = "${local.name_prefix}-postgres"
  server_type = var.postgres_server_type
  location    = var.location
  image       = "ubuntu-22.04"

  ssh_keys     = [var.ssh_key_id]
  firewall_ids = [var.firewall_id]

  labels = merge(local.common_labels, {
    service = "postgresql"
  })

  network {
    network_id = var.network_id
  }

  user_data = <<-EOF
    #cloud-config
    package_update: true
    package_upgrade: true

    packages:
      - postgresql-16
      - postgresql-contrib-16

    write_files:
      - path: /etc/postgresql/16/main/conf.d/custom.conf
        content: |
          listen_addresses = '*'
          max_connections = 200
          shared_buffers = 2GB
          effective_cache_size = 6GB
          maintenance_work_mem = 512MB
          checkpoint_completion_target = 0.9
          wal_buffers = 64MB
          default_statistics_target = 100
          random_page_cost = 1.1
          effective_io_concurrency = 200
          min_wal_size = 1GB
          max_wal_size = 4GB
          max_worker_processes = 4
          max_parallel_workers_per_gather = 2
          max_parallel_workers = 4
          max_parallel_maintenance_workers = 2
          # Logging
          log_statement = 'all'
          log_min_duration_statement = 1000
          shared_preload_libraries = 'pg_stat_statements'
          
      - path: /etc/postgresql/16/main/pg_hba.conf
        content: |
          local   all             postgres                                peer
          local   all             all                                     peer
          host    all             all             10.0.0.0/16             scram-sha-256
          host    all             all             127.0.0.1/32            scram-sha-256
          host    all             all             ::1/128                 scram-sha-256

    runcmd:
      # Mount volume
      - mkdir -p /mnt/postgres-data
      - mount -o discard,defaults /dev/disk/by-id/scsi-0HC_Volume_${hcloud_volume.postgres.id} /mnt/postgres-data
      - echo '/dev/disk/by-id/scsi-0HC_Volume_${hcloud_volume.postgres.id} /mnt/postgres-data ext4 discard,nofail,defaults 0 0' >> /etc/fstab
      
      # Stop PostgreSQL, move data, restart
      - systemctl stop postgresql
      - rsync -av /var/lib/postgresql/ /mnt/postgres-data/
      - rm -rf /var/lib/postgresql
      - ln -s /mnt/postgres-data /var/lib/postgresql
      - chown -R postgres:postgres /mnt/postgres-data
      
      # Restart and configure
      - systemctl start postgresql
      - systemctl enable postgresql
      
      # Create database and user
      - sudo -u postgres psql -c "CREATE USER nornos_admin WITH PASSWORD '${random_password.postgres.result}' SUPERUSER;"
      - sudo -u postgres psql -c "CREATE DATABASE nornos OWNER nornos_admin;"
      - sudo -u postgres psql -c "CREATE EXTENSION IF NOT EXISTS pg_stat_statements;"
      
      # Restart to apply config
      - systemctl restart postgresql
  EOF

  lifecycle {
    ignore_changes = [user_data]
  }
}

# Attach volume to PostgreSQL server
resource "hcloud_volume_attachment" "postgres" {
  volume_id = hcloud_volume.postgres.id
  server_id = hcloud_server.postgres.id
  automount = false
}

# Redis Server
resource "hcloud_server" "redis" {
  name        = "${local.name_prefix}-redis"
  server_type = var.redis_server_type
  location    = var.location
  image       = "ubuntu-22.04"

  ssh_keys     = [var.ssh_key_id]
  firewall_ids = [var.firewall_id]

  labels = merge(local.common_labels, {
    service = "redis"
  })

  network {
    network_id = var.network_id
  }

  user_data = <<-EOF
    #cloud-config
    package_update: true
    package_upgrade: true

    packages:
      - redis-server

    write_files:
      - path: /etc/redis/redis.conf
        content: |
          bind 0.0.0.0
          port 6379
          requirepass ${random_password.redis.result}
          
          # Memory management
          maxmemory 3gb
          maxmemory-policy allkeys-lru
          
          # Persistence
          appendonly yes
          appendfsync everysec
          
          # Security
          protected-mode yes
          
          # Performance
          tcp-backlog 511
          timeout 0
          tcp-keepalive 300
          
          # Logging
          loglevel notice
          logfile /var/log/redis/redis-server.log

    runcmd:
      - systemctl restart redis-server
      - systemctl enable redis-server
  EOF

  lifecycle {
    ignore_changes = [user_data]
  }
}

# Outputs
output "postgres_private_ip" {
  description = "PostgreSQL private IP"
  value       = hcloud_server.postgres.network[*].ip
}

output "postgres_public_ip" {
  description = "PostgreSQL public IP (for admin access)"
  value       = hcloud_server.postgres.ipv4_address
}

output "postgres_port" {
  description = "PostgreSQL port"
  value       = 5432
}

output "postgres_database" {
  description = "PostgreSQL database name"
  value       = "nornos"
}

output "postgres_username" {
  description = "PostgreSQL username"
  value       = "nornos_admin"
}

output "postgres_password" {
  description = "PostgreSQL password"
  value       = random_password.postgres.result
  sensitive   = true
}

output "postgres_connection_string" {
  description = "PostgreSQL connection string"
  value       = "postgresql://nornos_admin:${random_password.postgres.result}@${hcloud_server.postgres.network[0].ip}:5432/nornos"
  sensitive   = true
}

output "redis_private_ip" {
  description = "Redis private IP"
  value       = hcloud_server.redis.network[*].ip
}

output "redis_public_ip" {
  description = "Redis public IP (for admin access)"
  value       = hcloud_server.redis.ipv4_address
}

output "redis_port" {
  description = "Redis port"
  value       = 6379
}

output "redis_password" {
  description = "Redis password"
  value       = random_password.redis.result
  sensitive   = true
}

output "redis_connection_string" {
  description = "Redis connection string"
  value       = "redis://:${random_password.redis.result}@${hcloud_server.redis.network[0].ip}:6379/0"
  sensitive   = true
}

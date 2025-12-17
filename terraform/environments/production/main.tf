# Nornos Production Environment - Hetzner Cloud

terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.45"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11"
    }
  }

  # Remote backend for production state
  backend "s3" {
    bucket         = "nornos-terraform-state"
    key            = "production/terraform.tfstate"
    region         = "eu-central-1"  # Can use any S3-compatible storage
    encrypt        = true
  }
}

# Hetzner Cloud Provider
provider "hcloud" {
  token = var.hcloud_token
}

# Variables
variable "hcloud_token" {
  description = "Hetzner Cloud API token"
  type        = string
  sensitive   = true
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

variable "location" {
  description = "Hetzner Cloud location"
  type        = string
  default     = "fsn1"
}

variable "ssh_public_key" {
  description = "SSH public key for server access"
  type        = string
}

# Networking
module "networking" {
  source = "../../modules/networking"

  environment  = var.environment
  network_cidr = "10.0.0.0/16"
  location     = var.location

  tags = {
    environment = var.environment
  }
}

# Kubernetes (k3s HA cluster)
module "kubernetes" {
  source = "../../modules/kubernetes"

  environment          = var.environment
  network_id           = module.networking.network_id
  kubernetes_subnet_id = module.networking.kubernetes_subnet_id
  firewall_id          = module.networking.kubernetes_firewall_id
  location             = var.location
  ssh_public_key       = var.ssh_public_key
  
  # Production: HA setup with larger instances
  control_plane_type  = "cx31"  # 2 vCPU, 8GB RAM
  worker_type         = "cx41"  # 4 vCPU, 16GB RAM
  agent_worker_type   = "cx51"  # 8 vCPU, 32GB RAM
  
  control_plane_count = 3       # HA control plane
  worker_count        = 4       # More workers for redundancy
  agent_worker_count  = 3       # More AI processing capacity

  tags = {
    environment = var.environment
  }
}

# Database (PostgreSQL + Redis)
module "database" {
  source = "../../modules/database"

  environment        = var.environment
  network_id         = module.networking.network_id
  database_subnet_id = module.networking.database_subnet_id
  firewall_id        = module.networking.database_firewall_id
  ssh_key_id         = module.kubernetes.ssh_key_id
  location           = var.location
  
  # Production: larger instances
  postgres_server_type = "cx41"  # 4 vCPU, 16GB RAM
  redis_server_type    = "cx31"  # 2 vCPU, 8GB RAM
  postgres_volume_size = 500     # 500GB for production data

  tags = {
    environment = var.environment
  }

  depends_on = [module.kubernetes]
}

# Outputs
output "cluster_info" {
  description = "Kubernetes cluster information"
  value = {
    control_plane_ips = module.kubernetes.control_plane_ips
    load_balancer_ip  = module.kubernetes.load_balancer_ip
    worker_ips        = module.kubernetes.worker_ips
    agent_worker_ips  = module.kubernetes.agent_worker_ips
  }
}

output "database_info" {
  description = "Database connection information"
  value = {
    postgres_host = module.database.postgres_private_ip[0]
    postgres_port = module.database.postgres_port
    redis_host    = module.database.redis_private_ip[0]
    redis_port    = module.database.redis_port
  }
}

output "postgres_connection_string" {
  description = "PostgreSQL connection string"
  value       = module.database.postgres_connection_string
  sensitive   = true
}

output "redis_connection_string" {
  description = "Redis connection string"
  value       = module.database.redis_connection_string
  sensitive   = true
}

output "kubeconfig_command" {
  description = "Command to get kubeconfig"
  value       = module.kubernetes.kubeconfig_command
}

output "monthly_cost_estimate" {
  description = "Estimated monthly cost (EUR)"
  value = {
    control_plane = "€8.98 x 3 = €26.94"
    workers       = "€17.85 x 4 = €71.40"
    agent_workers = "€35.58 x 3 = €106.74"
    postgres      = "€17.85 + €23.00 (500GB) = €40.85"
    redis         = "€8.98"
    load_balancer = "€5.39"
    total         = "~€260/month"
  }
}

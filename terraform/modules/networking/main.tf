# Nornos Networking Module - Hetzner Cloud

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.45"
    }
  }
}

# Variables
variable "environment" {
  description = "Environment name (dev, staging, production)"
  type        = string
}

variable "network_cidr" {
  description = "CIDR block for the network"
  type        = string
  default     = "10.0.0.0/16"
}

variable "location" {
  description = "Hetzner Cloud location"
  type        = string
  default     = "fsn1" # Falkenstein, Germany
}

variable "tags" {
  description = "Common tags for all resources"
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

# Private Network
resource "hcloud_network" "main" {
  name     = "${local.name_prefix}-network"
  ip_range = var.network_cidr

  labels = local.common_labels
}

# Subnet for Kubernetes nodes
resource "hcloud_network_subnet" "kubernetes" {
  network_id   = hcloud_network.main.id
  type         = "cloud"
  network_zone = "eu-central"
  ip_range     = cidrsubnet(var.network_cidr, 8, 1) # 10.0.1.0/24
}

# Subnet for databases
resource "hcloud_network_subnet" "database" {
  network_id   = hcloud_network.main.id
  type         = "cloud"
  network_zone = "eu-central"
  ip_range     = cidrsubnet(var.network_cidr, 8, 2) # 10.0.2.0/24
}

# Subnet for load balancers
resource "hcloud_network_subnet" "loadbalancer" {
  network_id   = hcloud_network.main.id
  type         = "cloud"
  network_zone = "eu-central"
  ip_range     = cidrsubnet(var.network_cidr, 8, 3) # 10.0.3.0/24
}

# Firewall for Kubernetes nodes
resource "hcloud_firewall" "kubernetes" {
  name = "${local.name_prefix}-k8s-firewall"

  labels = local.common_labels

  # SSH access (restrict in production)
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  # Kubernetes API
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "6443"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  # HTTP/HTTPS
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "80"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "443"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  # NodePort range
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "30000-32767"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  # Internal cluster communication
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "any"
    source_ips = [var.network_cidr]
  }

  rule {
    direction  = "in"
    protocol   = "udp"
    port       = "any"
    source_ips = [var.network_cidr]
  }

  # ICMP
  rule {
    direction  = "in"
    protocol   = "icmp"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  # Allow all outbound
  rule {
    direction       = "out"
    protocol        = "tcp"
    port            = "any"
    destination_ips = ["0.0.0.0/0", "::/0"]
  }

  rule {
    direction       = "out"
    protocol        = "udp"
    port            = "any"
    destination_ips = ["0.0.0.0/0", "::/0"]
  }

  rule {
    direction       = "out"
    protocol        = "icmp"
    destination_ips = ["0.0.0.0/0", "::/0"]
  }
}

# Firewall for database servers
resource "hcloud_firewall" "database" {
  name = "${local.name_prefix}-db-firewall"

  labels = local.common_labels

  # PostgreSQL - only from internal network
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "5432"
    source_ips = [var.network_cidr]
  }

  # Redis - only from internal network
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "6379"
    source_ips = [var.network_cidr]
  }

  # SSH - only from internal network
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = [var.network_cidr]
  }

  # Allow all outbound
  rule {
    direction       = "out"
    protocol        = "tcp"
    port            = "any"
    destination_ips = ["0.0.0.0/0", "::/0"]
  }
}

# Outputs
output "network_id" {
  description = "Network ID"
  value       = hcloud_network.main.id
}

output "network_cidr" {
  description = "Network CIDR"
  value       = hcloud_network.main.ip_range
}

output "kubernetes_subnet_id" {
  description = "Kubernetes subnet ID"
  value       = hcloud_network_subnet.kubernetes.id
}

output "database_subnet_id" {
  description = "Database subnet ID"
  value       = hcloud_network_subnet.database.id
}

output "kubernetes_firewall_id" {
  description = "Kubernetes firewall ID"
  value       = hcloud_firewall.kubernetes.id
}

output "database_firewall_id" {
  description = "Database firewall ID"
  value       = hcloud_firewall.database.id
}

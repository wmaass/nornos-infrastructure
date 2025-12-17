# Nornos Kubernetes Module - Hetzner Cloud (k3s)

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.45"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
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

variable "kubernetes_subnet_id" {
  description = "Kubernetes subnet ID"
  type        = string
}

variable "firewall_id" {
  description = "Firewall ID for nodes"
  type        = number
}

variable "location" {
  description = "Hetzner Cloud location"
  type        = string
  default     = "fsn1"
}

variable "control_plane_type" {
  description = "Server type for control plane nodes"
  type        = string
  default     = "cx31" # 2 vCPU, 8GB RAM
}

variable "worker_type" {
  description = "Server type for worker nodes"
  type        = string
  default     = "cx41" # 4 vCPU, 16GB RAM
}

variable "agent_worker_type" {
  description = "Server type for agent processing workers (larger)"
  type        = string
  default     = "cx51" # 8 vCPU, 32GB RAM
}

variable "control_plane_count" {
  description = "Number of control plane nodes"
  type        = number
  default     = 1 # 3 for HA in production
}

variable "worker_count" {
  description = "Number of general worker nodes"
  type        = number
  default     = 2
}

variable "agent_worker_count" {
  description = "Number of agent processing workers"
  type        = number
  default     = 1
}

variable "ssh_public_key" {
  description = "SSH public key for server access"
  type        = string
  default     = ""
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

  k3s_version = "v1.29.0+k3s1"
}

# Generate SSH key if not provided
resource "tls_private_key" "ssh" {
  count     = var.ssh_public_key == "" ? 1 : 0
  algorithm = "ED25519"
}

# SSH Key
resource "hcloud_ssh_key" "main" {
  name       = "${local.name_prefix}-ssh-key"
  public_key = var.ssh_public_key != "" ? var.ssh_public_key : tls_private_key.ssh[0].public_key_openssh

  labels = local.common_labels
}

# Placement Group for spreading nodes across hosts
resource "hcloud_placement_group" "kubernetes" {
  name = "${local.name_prefix}-k8s-spread"
  type = "spread"

  labels = local.common_labels
}

# Generate k3s token
resource "random_password" "k3s_token" {
  length  = 64
  special = false
}

# Control Plane Node(s)
resource "hcloud_server" "control_plane" {
  count = var.control_plane_count

  name        = "${local.name_prefix}-cp-${count.index + 1}"
  server_type = var.control_plane_type
  location    = var.location
  image       = "ubuntu-22.04"

  ssh_keys         = [hcloud_ssh_key.main.id]
  firewall_ids     = [var.firewall_id]
  placement_group_id = hcloud_placement_group.kubernetes.id

  labels = merge(local.common_labels, {
    role = "control-plane"
  })

  network {
    network_id = var.network_id
  }

  user_data = <<-EOF
    #cloud-config
    package_update: true
    package_upgrade: true
    
    packages:
      - curl
      - apt-transport-https
      - ca-certificates

    write_files:
      - path: /etc/rancher/k3s/config.yaml
        content: |
          cluster-init: ${count.index == 0 ? "true" : "false"}
          token: "${random_password.k3s_token.result}"
          tls-san:
            - "${local.name_prefix}-cp-${count.index + 1}"
          disable:
            - traefik
          node-label:
            - "node.kubernetes.io/role=control-plane"

    runcmd:
      - curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="${local.k3s_version}" sh -s - server
      - sleep 30
      # Install Helm
      - curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  EOF

  lifecycle {
    ignore_changes = [user_data]
  }
}

# General Worker Nodes
resource "hcloud_server" "worker" {
  count = var.worker_count

  name        = "${local.name_prefix}-worker-${count.index + 1}"
  server_type = var.worker_type
  location    = var.location
  image       = "ubuntu-22.04"

  ssh_keys         = [hcloud_ssh_key.main.id]
  firewall_ids     = [var.firewall_id]
  placement_group_id = hcloud_placement_group.kubernetes.id

  labels = merge(local.common_labels, {
    role = "worker"
  })

  network {
    network_id = var.network_id
  }

  user_data = <<-EOF
    #cloud-config
    package_update: true
    package_upgrade: true
    
    packages:
      - curl

    runcmd:
      - |
        until curl -sf http://${hcloud_server.control_plane[0].ipv4_address}:6443/healthz; do
          echo "Waiting for control plane..."
          sleep 10
        done
      - curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="${local.k3s_version}" K3S_URL="https://${hcloud_server.control_plane[0].ipv4_address}:6443" K3S_TOKEN="${random_password.k3s_token.result}" sh -s - agent --node-label="node.kubernetes.io/role=worker"
  EOF

  depends_on = [hcloud_server.control_plane]

  lifecycle {
    ignore_changes = [user_data]
  }
}

# Agent Processing Workers (larger nodes for AI workloads)
resource "hcloud_server" "agent_worker" {
  count = var.agent_worker_count

  name        = "${local.name_prefix}-agent-${count.index + 1}"
  server_type = var.agent_worker_type
  location    = var.location
  image       = "ubuntu-22.04"

  ssh_keys         = [hcloud_ssh_key.main.id]
  firewall_ids     = [var.firewall_id]
  placement_group_id = hcloud_placement_group.kubernetes.id

  labels = merge(local.common_labels, {
    role     = "agent-worker"
    workload = "ai-processing"
  })

  network {
    network_id = var.network_id
  }

  user_data = <<-EOF
    #cloud-config
    package_update: true
    package_upgrade: true
    
    packages:
      - curl

    runcmd:
      - |
        until curl -sf http://${hcloud_server.control_plane[0].ipv4_address}:6443/healthz; do
          echo "Waiting for control plane..."
          sleep 10
        done
      - curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="${local.k3s_version}" K3S_URL="https://${hcloud_server.control_plane[0].ipv4_address}:6443" K3S_TOKEN="${random_password.k3s_token.result}" sh -s - agent --node-label="node.kubernetes.io/role=agent" --node-label="workload=ai-processing" --node-taint="workload=ai-processing:NoSchedule"
  EOF

  depends_on = [hcloud_server.control_plane]

  lifecycle {
    ignore_changes = [user_data]
  }
}

# Load Balancer for ingress
resource "hcloud_load_balancer" "ingress" {
  name               = "${local.name_prefix}-ingress-lb"
  load_balancer_type = "lb11"
  location           = var.location

  labels = local.common_labels
}

resource "hcloud_load_balancer_network" "ingress" {
  load_balancer_id = hcloud_load_balancer.ingress.id
  network_id       = var.network_id
}

resource "hcloud_load_balancer_target" "workers" {
  count = var.worker_count

  type             = "server"
  load_balancer_id = hcloud_load_balancer.ingress.id
  server_id        = hcloud_server.worker[count.index].id
  use_private_ip   = true

  depends_on = [hcloud_load_balancer_network.ingress]
}

resource "hcloud_load_balancer_service" "http" {
  load_balancer_id = hcloud_load_balancer.ingress.id
  protocol         = "tcp"
  listen_port      = 80
  destination_port = 80

  health_check {
    protocol = "tcp"
    port     = 80
    interval = 10
    timeout  = 5
    retries  = 3
  }
}

resource "hcloud_load_balancer_service" "https" {
  load_balancer_id = hcloud_load_balancer.ingress.id
  protocol         = "tcp"
  listen_port      = 443
  destination_port = 443

  health_check {
    protocol = "tcp"
    port     = 443
    interval = 10
    timeout  = 5
    retries  = 3
  }
}

# Outputs
output "control_plane_ips" {
  description = "Control plane public IPs"
  value       = hcloud_server.control_plane[*].ipv4_address
}

output "control_plane_private_ips" {
  description = "Control plane private IPs"
  value       = [for s in hcloud_server.control_plane : s.network[*].ip]
}

output "worker_ips" {
  description = "Worker public IPs"
  value       = hcloud_server.worker[*].ipv4_address
}

output "agent_worker_ips" {
  description = "Agent worker public IPs"
  value       = hcloud_server.agent_worker[*].ipv4_address
}

output "load_balancer_ip" {
  description = "Load balancer public IP"
  value       = hcloud_load_balancer.ingress.ipv4
}

output "k3s_token" {
  description = "K3s cluster token"
  value       = random_password.k3s_token.result
  sensitive   = true
}

output "ssh_private_key" {
  description = "SSH private key (if generated)"
  value       = var.ssh_public_key == "" ? tls_private_key.ssh[0].private_key_openssh : null
  sensitive   = true
}

output "kubeconfig_command" {
  description = "Command to get kubeconfig"
  value       = "scp root@${hcloud_server.control_plane[0].ipv4_address}:/etc/rancher/k3s/k3s.yaml ./kubeconfig && sed -i '' 's/127.0.0.1/${hcloud_server.control_plane[0].ipv4_address}/g' ./kubeconfig"
}

output "ssh_key_id" {
  description = "SSH key ID"
  value       = hcloud_ssh_key.main.id
}

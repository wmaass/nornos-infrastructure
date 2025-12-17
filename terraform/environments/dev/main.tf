# Nornos Development Environment

terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
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

  backend "s3" {
    bucket         = "nornos-terraform-state"
    key            = "dev/terraform.tfstate"
    region         = "eu-central-1"
    encrypt        = true
    dynamodb_table = "nornos-terraform-locks"
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = "dev"
      Project     = "nornos"
      ManagedBy   = "terraform"
    }
  }
}

# Variables
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-central-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

# Networking
module "networking" {
  source = "../../modules/networking"

  environment        = var.environment
  vpc_cidr           = "10.0.0.0/16"
  availability_zones = ["eu-central-1a", "eu-central-1b"]

  tags = {
    Environment = var.environment
  }
}

# Kubernetes (EKS)
module "kubernetes" {
  source = "../../modules/kubernetes"

  environment         = var.environment
  vpc_id              = module.networking.vpc_id
  private_subnet_ids  = module.networking.private_subnet_ids
  public_subnet_ids   = module.networking.public_subnet_ids
  kubernetes_version  = "1.29"
  
  node_instance_types = ["t3.large"]
  node_desired_size   = 2
  node_min_size       = 1
  node_max_size       = 5

  tags = {
    Environment = var.environment
  }
}

# Configure Kubernetes provider
provider "kubernetes" {
  host                   = module.kubernetes.cluster_endpoint
  cluster_ca_certificate = base64decode(module.kubernetes.cluster_certificate_authority)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.kubernetes.cluster_name]
  }
}

provider "helm" {
  kubernetes {
    host                   = module.kubernetes.cluster_endpoint
    cluster_ca_certificate = base64decode(module.kubernetes.cluster_certificate_authority)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.kubernetes.cluster_name]
    }
  }
}

# Database
module "database" {
  source = "../../modules/database"

  environment             = var.environment
  vpc_id                  = module.networking.vpc_id
  database_subnet_ids     = module.networking.database_subnet_ids
  allowed_security_groups = [module.kubernetes.cluster_security_group_id]

  instance_class          = "db.t3.medium"
  allocated_storage       = 50
  max_allocated_storage   = 100
  multi_az                = false  # Single AZ for dev
  backup_retention_period = 3

  tags = {
    Environment = var.environment
  }
}

# S3 Bucket for Object Storage
resource "aws_s3_bucket" "storage" {
  bucket = "nornos-${var.environment}-storage"

  tags = {
    Name        = "nornos-${var.environment}-storage"
    Environment = var.environment
  }
}

resource "aws_s3_bucket_versioning" "storage" {
  bucket = aws_s3_bucket.storage.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "storage" {
  bucket = aws_s3_bucket.storage.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "storage" {
  bucket = aws_s3_bucket.storage.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ECR Repositories for Docker Images
resource "aws_ecr_repository" "services" {
  for_each = toset([
    "patient-app",
    "doctor-app",
    "agent-service",
    "relay-server",
    "shared-data-server",
    "auth-service",
    "vault-server"
  ])

  name                 = "nornos/${each.key}"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name        = "nornos/${each.key}"
    Environment = var.environment
  }
}

# Outputs
output "vpc_id" {
  description = "VPC ID"
  value       = module.networking.vpc_id
}

output "eks_cluster_name" {
  description = "EKS cluster name"
  value       = module.kubernetes.cluster_name
}

output "eks_cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = module.kubernetes.cluster_endpoint
}

output "database_endpoint" {
  description = "Database endpoint"
  value       = module.database.database_endpoint
}

output "redis_endpoint" {
  description = "Redis endpoint"
  value       = module.database.redis_endpoint
}

output "s3_bucket" {
  description = "S3 bucket name"
  value       = aws_s3_bucket.storage.bucket
}

output "ecr_repositories" {
  description = "ECR repository URLs"
  value       = { for k, v in aws_ecr_repository.services : k => v.repository_url }
}

output "kubeconfig_command" {
  description = "Command to configure kubectl"
  value       = "aws eks update-kubeconfig --name ${module.kubernetes.cluster_name} --region ${var.aws_region}"
}

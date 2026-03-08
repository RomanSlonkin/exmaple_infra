# =============================================================================
# VPC - Networking foundation for EKS
# Creates VPC with public/private subnets across 2 AZs
# =============================================================================
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws" # Official AWS VPC module
  version = "~> 5.0"                        # Stable version

  # VPC basics
  name = "todolist-vpc" # Unique name for resources
  cidr = "10.0.0.0/16"  # /16 = plenty of IP space

  # Subnets across 2 AZs for HA
  azs             = ["us-east-1a", "us-east-1b"]       # Match your AWS region
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]     # EKS nodes live here
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"] # ALB/Ingress live here

  # Internet access for private subnets (required for EKS nodes)
  enable_nat_gateway = true
  single_nat_gateway = true # Cost optimization (1 NAT vs 2)

  # EKS subnet discovery tags (critical!)
  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1 # Public subnets for LoadBalancers
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1 # Private subnets for internal services
  }

  # Global tags for organization
  tags = {
    KubernetesCluster = var.cluster_name # EKS auto-discovers
    Environment       = "portfolio"
    ManagedBy         = "terraform"
  }
}

# =============================================================================
# EKS Cluster - Managed Kubernetes control plane + worker nodes
# =============================================================================
module "eks" {
  source  = "terraform-aws-modules/eks/aws" # Official AWS EKS module
  version = "~> 20.0"                       # Compatible with K8s 1.30

  # Cluster identity
  cluster_name    = var.cluster_name # Must be unique in account
  cluster_version = "1.30"           # Latest stable Kubernetes

  # Network integration
  vpc_id                         = module.vpc.vpc_id          # VPC created above
  subnet_ids                     = module.vpc.private_subnets # Nodes in private subnets
  cluster_endpoint_public_access = true                       # Allow kubectl from internet

  # Managed node groups (EC2 instances running Kubernetes)
  eks_managed_node_groups = {
    general = {
      # Auto-scaling
      min_size     = 1 # Minimum 1 node for demo
      max_size     = 3 # Scale up to 3 under load
      desired_size = 2 # Start with 2

      # Instance config (cheap for portfolio)
      instance_types = ["t3.small"] # ~$0.02/hour each
      capacity_type  = "ON_DEMAND"  # Reliable (not spot)

      # Update strategy
      create_before_destroy = true
    }
  }

  # Permissions for terraform/kubeconfig access
  enable_cluster_creator_admin_permissions = true

  # Tags for cost tracking
  tags = {
    Environment = "portfolio"
    Purpose     = "devops-portfolio"
  }
}

# =============================================================================
# Kubernetes Namespaces - Logical isolation for environments
# Depends on EKS being healthy first
# =============================================================================
resource "kubernetes_namespace" "dev" {
  metadata {
    name = "dev"
  }
  depends_on = [module.eks] # Wait for EKS control plane
}

resource "kubernetes_namespace" "stage" {
  metadata {
    name = "stage"
  }
  depends_on = [module.eks]
}

resource "kubernetes_namespace" "prod" {
  metadata {
    name = "prod"
  }
  depends_on = [module.eks]
}

resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = "monitoring"
  }
  depends_on = [module.eks]
}

resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd" # GitOps controller
  }
  depends_on = [module.eks]
}

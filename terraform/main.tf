terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.80, < 7.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  backend "s3" {
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

locals {
  cluster_name                = "starttech-cluster"
  selected_availability_zones = length(var.availability_zones) >= 2 ? slice(var.availability_zones, 0, 2) : slice(data.aws_availability_zones.available.names, 0, 2)
  frontend_bucket_name        = "starttech-frontend-bucket-${data.aws_caller_identity.current.account_id}"

  common_tags = merge(var.additional_tags, {
    Project     = "StartTech"
    Environment = var.environment
    ManagedBy   = "Terraform"
  })
}

module "networking" {
  source = "./modules/networking"

  vpc_cidr           = var.vpc_cidr
  availability_zones = local.selected_availability_zones
  cluster_name       = local.cluster_name
  tags               = local.common_tags
}

module "eks" {
  source = "./modules/eks"

  cluster_name        = local.cluster_name
  cluster_version     = var.cluster_version
  vpc_id              = module.networking.vpc_id
  private_subnet_ids  = module.networking.private_subnet_ids
  node_instance_types = var.node_instance_types
  desired_nodes       = var.desired_nodes
  minimum_nodes       = var.minimum_nodes
  maximum_nodes       = var.maximum_nodes
  tags                = local.common_tags
}

module "storage" {
  source = "./modules/storage"

  frontend_bucket_name = local.frontend_bucket_name
  ecr_repository_name  = "starttech-backend-api"
  tags                 = local.common_tags
}

module "database" {
  source = "./modules/database"

  vpc_id                       = module.networking.vpc_id
  database_subnet_ids          = module.networking.database_subnet_ids
  eks_worker_security_group_id = module.eks.cluster_security_group_id
  tags                         = local.common_tags
}

module "cdn" {
  source = "./modules/cdn"

  vpc_id                               = module.networking.vpc_id
  public_subnet_ids                    = module.networking.public_subnet_ids
  eks_worker_security_group_id         = module.eks.cluster_security_group_id
  node_autoscaling_group_name          = module.eks.node_autoscaling_group_name
  frontend_bucket_regional_domain_name = module.storage.frontend_bucket_regional_domain_name
  tags                                 = local.common_tags
}

data "aws_iam_policy_document" "frontend_bucket" {
  statement {
    sid       = "AllowCloudFrontReadOnly"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${module.storage.frontend_bucket_arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [module.cdn.distribution_arn]
    }
  }
}

resource "aws_s3_bucket_policy" "frontend" {
  bucket = module.storage.frontend_bucket_name
  policy = data.aws_iam_policy_document.frontend_bucket.json
}

data "tls_certificate" "github_actions" {
  url = "https://token.actions.githubusercontent.com/.well-known/openid-configuration"
}

resource "aws_iam_openid_connect_provider" "github_actions" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github_actions.certificates[0].sha1_fingerprint]

  tags = local.common_tags
}

data "aws_iam_policy_document" "infrastructure_github_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github_actions.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_owner}/${var.infrastructure_repository}:*"]
    }
  }
}

resource "aws_iam_role" "infrastructure_github" {
  name               = "starttech-github-infrastructure-role"
  assume_role_policy = data.aws_iam_policy_document.infrastructure_github_trust.json
  tags               = local.common_tags
}

data "aws_iam_policy_document" "infrastructure_github" {
  statement {
    sid    = "ManageStartTechInfrastructure"
    effect = "Allow"
    actions = [
      "autoscaling:*",
      "cloudfront:*",
      "ec2:*",
      "ecr:*",
      "eks:*",
      "elasticache:*",
      "elasticloadbalancing:*",
      "iam:*",
      "logs:*",
      "s3:*",
      "sts:GetCallerIdentity"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "infrastructure_github" {
  name   = "starttech-infrastructure-deployment"
  role   = aws_iam_role.infrastructure_github.id
  policy = data.aws_iam_policy_document.infrastructure_github.json
}

data "aws_iam_policy_document" "application_github_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github_actions.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_owner}/${var.application_repository}:*"]
    }
  }
}

resource "aws_iam_role" "application_github" {
  name               = "starttech-github-application-role"
  assume_role_policy = data.aws_iam_policy_document.application_github_trust.json
  tags               = local.common_tags
}

data "aws_iam_policy_document" "application_github" {
  statement {
    sid       = "ECRAuthentication"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid    = "BackendImageDelivery"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:CompleteLayerUpload",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart"
    ]
    resources = ["arn:${data.aws_partition.current.partition}:ecr:${var.aws_region}:${data.aws_caller_identity.current.account_id}:repository/starttech-backend-api"]
  }

  statement {
    sid       = "ClusterAndCacheDiscovery"
    effect    = "Allow"
    actions   = ["eks:DescribeCluster", "elasticache:DescribeCacheClusters"]
    resources = ["*"]
  }

  statement {
    sid    = "FrontendDelivery"
    effect = "Allow"
    actions = [
      "s3:DeleteObject",
      "s3:GetBucketLocation",
      "s3:ListBucket",
      "s3:PutObject"
    ]
    resources = [module.storage.frontend_bucket_arn, "${module.storage.frontend_bucket_arn}/*"]
  }

  statement {
    sid       = "CloudFrontInvalidation"
    effect    = "Allow"
    actions   = ["cloudfront:CreateInvalidation"]
    resources = [module.cdn.distribution_arn]
  }
}

resource "aws_iam_role_policy" "application_github" {
  name   = "starttech-application-deployment"
  role   = aws_iam_role.application_github.id
  policy = data.aws_iam_policy_document.application_github.json
}

resource "aws_eks_access_entry" "application_github" {
  cluster_name  = module.eks.cluster_name
  principal_arn = aws_iam_role.application_github.arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "application_github" {
  cluster_name  = module.eks.cluster_name
  principal_arn = aws_iam_role.application_github.arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.application_github]
}

resource "aws_iam_user" "start_tech_grader" {
  name = "start-tech-grader"
  tags = local.common_tags
}

resource "aws_iam_user_policy" "start_tech_grader" {
  name = "StartTechGraderReadOnly"
  user = aws_iam_user.start_tech_grader.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "GraderReadOnlyS3"
        Effect   = "Allow"
        Action   = ["s3:ListAllMyBuckets", "s3:GetBucketPublicAccessBlock", "s3:ListBucket"]
        Resource = "*"
      },
      {
        Sid      = "GraderReadOnlyCloudFront"
        Effect   = "Allow"
        Action   = ["cloudfront:ListDistributions", "cloudfront:GetDistributionConfig"]
        Resource = "*"
      },
      {
        Sid      = "GraderReadOnlyEKS"
        Effect   = "Allow"
        Action   = ["eks:DescribeCluster", "eks:ListNodegroups", "eks:DescribeNodegroup"]
        Resource = "*"
      },
      {
        Sid      = "GraderReadOnlyElastiCache"
        Effect   = "Allow"
        Action   = ["elasticache:DescribeCacheClusters"]
        Resource = "*"
      }
    ]
  })
}

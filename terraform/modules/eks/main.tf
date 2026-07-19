data "aws_iam_policy_document" "cluster_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cluster" {
  name               = "starttech-eks-cluster-role"
  assume_role_policy = data.aws_iam_policy_document.cluster_assume_role.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_eks_cluster" "starttech_cluster" {
  name     = var.cluster_name
  role_arn = aws_iam_role.cluster.arn
  version  = var.cluster_version

  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  vpc_config {
    subnet_ids              = var.private_subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = true
  }

  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  tags = merge(var.tags, {
    Name = var.cluster_name
  })

  depends_on = [aws_iam_role_policy_attachment.cluster_policy]
}

data "aws_iam_policy_document" "node_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "nodes" {
  name               = "starttech-eks-node-role"
  assume_role_policy = data.aws_iam_policy_document.node_assume_role.json
  tags               = var.tags
}

locals {
  node_policy_arns = {
    worker = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
    ecr    = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
    cni    = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  }
}

resource "aws_iam_role_policy_attachment" "nodes" {
  for_each = local.node_policy_arns

  role       = aws_iam_role.nodes.name
  policy_arn = each.value
}

resource "aws_eks_node_group" "starttech_node_group" {
  cluster_name    = aws_eks_cluster.starttech_cluster.name
  node_group_name = "starttech-node-group"
  node_role_arn   = aws_iam_role.nodes.arn
  subnet_ids      = var.private_subnet_ids
  instance_types  = var.node_instance_types
  capacity_type   = "ON_DEMAND"

  scaling_config {
    desired_size = var.desired_nodes
    min_size     = var.minimum_nodes
    max_size     = var.maximum_nodes
  }

  update_config {
    max_unavailable = 1
  }

  labels = {
    role = "application"
  }

  tags = merge(var.tags, {
    Name = "starttech-node-group"
  })

  depends_on = [aws_iam_role_policy_attachment.nodes]
}

resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = aws_eks_cluster.starttech_cluster.name
  addon_name                  = "vpc-cni"
  resolve_conflicts_on_update = "PRESERVE"

  depends_on = [aws_eks_node_group.starttech_node_group]
}

resource "aws_eks_addon" "coredns" {
  cluster_name                = aws_eks_cluster.starttech_cluster.name
  addon_name                  = "coredns"
  resolve_conflicts_on_update = "PRESERVE"

  depends_on = [aws_eks_node_group.starttech_node_group]
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name                = aws_eks_cluster.starttech_cluster.name
  addon_name                  = "kube-proxy"
  resolve_conflicts_on_update = "PRESERVE"

  depends_on = [aws_eks_node_group.starttech_node_group]
}

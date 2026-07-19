output "vpc_id" {
  value = module.networking.vpc_id
}

output "eks_cluster_name" {
  value = module.eks.cluster_name
}

output "eks_node_group_name" {
  value = module.eks.node_group_name
}

output "frontend_bucket_name" {
  value = module.storage.frontend_bucket_name
}

output "ecr_repository_url" {
  value = module.storage.ecr_repository_url
}

output "redis_endpoint" {
  value = module.database.redis_endpoint
}

output "backend_alb_dns_name" {
  value = module.cdn.alb_dns_name
}

output "cloudfront_distribution_id" {
  value = module.cdn.distribution_id
}

output "cloudfront_domain_name" {
  value = module.cdn.distribution_domain_name
}

output "infrastructure_github_role_arn" {
  value = aws_iam_role.infrastructure_github.arn
}

output "application_github_role_arn" {
  value = aws_iam_role.application_github.arn
}

output "grader_user_name" {
  value = aws_iam_user.start_tech_grader.name
}

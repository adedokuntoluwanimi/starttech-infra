output "distribution_id" {
  value = aws_cloudfront_distribution.starttech.id
}

output "distribution_arn" {
  value = aws_cloudfront_distribution.starttech.arn
}

output "distribution_domain_name" {
  value = aws_cloudfront_distribution.starttech.domain_name
}

output "alb_dns_name" {
  value = aws_lb.backend.dns_name
}

output "alb_arn" {
  value = aws_lb.backend.arn
}

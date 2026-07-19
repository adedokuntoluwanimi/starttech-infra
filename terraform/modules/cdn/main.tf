data "aws_ec2_managed_prefix_list" "cloudfront" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

resource "aws_security_group" "alb" {
  name        = "starttech-backend-alb-sg"
  description = "HTTP access from CloudFront to the StartTech backend ALB"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name = "starttech-backend-alb-sg"
  })
}

resource "aws_vpc_security_group_ingress_rule" "alb_from_cloudfront" {
  security_group_id = aws_security_group.alb.id
  prefix_list_id    = data.aws_ec2_managed_prefix_list.cloudfront.id
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
  description       = "HTTP from CloudFront origin-facing network"
}

resource "aws_vpc_security_group_egress_rule" "alb_to_eks" {
  security_group_id            = aws_security_group.alb.id
  referenced_security_group_id = var.eks_worker_security_group_id
  from_port                    = 30080
  to_port                      = 30080
  ip_protocol                  = "tcp"
  description                  = "Backend NodePort on EKS workers"
}

resource "aws_vpc_security_group_ingress_rule" "eks_from_alb" {
  security_group_id            = var.eks_worker_security_group_id
  referenced_security_group_id = aws_security_group.alb.id
  from_port                    = 30080
  to_port                      = 30080
  ip_protocol                  = "tcp"
  description                  = "Backend NodePort from the public ALB"
}

resource "aws_lb" "backend" {
  name                       = "starttech-backend-alb"
  internal                   = false
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.alb.id]
  subnets                    = var.public_subnet_ids
  drop_invalid_header_fields = true

  tags = merge(var.tags, {
    Name = "starttech-backend-alb"
  })
}

resource "aws_lb_target_group" "backend" {
  name        = "starttech-backend-tg"
  port        = 30080
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = var.vpc_id

  health_check {
    enabled             = true
    path                = "/api/v1/health"
    protocol            = "HTTP"
    port                = "traffic-port"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 5
    matcher             = "200"
  }

  tags = merge(var.tags, {
    Name = "starttech-backend-tg"
  })
}

resource "aws_autoscaling_attachment" "backend" {
  for_each = toset(var.node_autoscaling_group_names)

  autoscaling_group_name = each.value
  lb_target_group_arn    = aws_lb_target_group.backend.arn
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.backend.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend.arn
  }
}

resource "aws_cloudfront_origin_access_control" "frontend" {
  name                              = "starttech-frontend-oac"
  description                       = "Private access from CloudFront to the StartTech frontend bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "starttech" {
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  comment             = "StartTech unified frontend and backend distribution"
  price_class         = "PriceClass_100"

  origin {
    domain_name              = var.frontend_bucket_regional_domain_name
    origin_id                = "S3-Frontend"
    origin_access_control_id = aws_cloudfront_origin_access_control.frontend.id
  }

  origin {
    domain_name = aws_lb.backend.dns_name
    origin_id   = "ALB-Backend"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id       = "S3-Frontend"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    min_ttl     = 0
    default_ttl = 3600
    max_ttl     = 86400
  }

  ordered_cache_behavior {
    path_pattern           = "/api/*"
    target_origin_id       = "ALB-Backend"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    forwarded_values {
      query_string = true
      headers      = ["*"]

      cookies {
        forward = "all"
      }
    }

    min_ttl     = 0
    default_ttl = 0
    max_ttl     = 0
  }

  custom_error_response {
    error_code            = 403
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 0
  }

  custom_error_response {
    error_code            = 404
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 0
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
    minimum_protocol_version       = "TLSv1.2_2021"
  }

  tags = merge(var.tags, {
    Name = "starttech-cloudfront"
  })

  depends_on = [aws_lb_listener.http, aws_autoscaling_attachment.backend]
}

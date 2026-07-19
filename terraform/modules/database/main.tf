resource "aws_security_group" "redis" {
  name        = "starttech-redis-sg"
  description = "Allow Redis only from EKS workers"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name = "starttech-redis-sg"
  })
}

resource "aws_vpc_security_group_ingress_rule" "redis_from_eks" {
  security_group_id            = aws_security_group.redis.id
  referenced_security_group_id = var.eks_worker_security_group_id
  from_port                    = 6379
  to_port                      = 6379
  ip_protocol                  = "tcp"
  description                  = "Redis from EKS worker nodes"
}

resource "aws_vpc_security_group_egress_rule" "redis" {
  security_group_id = aws_security_group.redis.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_elasticache_subnet_group" "starttech" {
  name       = "starttech-redis-subnets"
  subnet_ids = var.database_subnet_ids
}

resource "aws_elasticache_cluster" "starttech_redis" {
  cluster_id           = "starttech-redis"
  engine               = "redis"
  engine_version       = "7.1"
  node_type            = "cache.t3.micro"
  num_cache_nodes      = 1
  parameter_group_name = "default.redis7"
  port                 = 6379
  subnet_group_name    = aws_elasticache_subnet_group.starttech.name
  security_group_ids   = [aws_security_group.redis.id]

  snapshot_retention_limit = 1
  maintenance_window       = "sun:03:00-sun:04:00"

  tags = merge(var.tags, {
    Name = "starttech-redis"
  })
}

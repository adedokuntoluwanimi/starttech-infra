variable "vpc_id" {
  type = string
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "eks_worker_security_group_id" {
  type = string
}

variable "node_autoscaling_group_names" {
  type = list(string)
}

variable "frontend_bucket_regional_domain_name" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}

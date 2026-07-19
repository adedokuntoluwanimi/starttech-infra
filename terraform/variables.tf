variable "aws_region" {
  description = "AWS region for regional StartTech resources."
  type        = string
  default     = "eu-west-1"
}

variable "environment" {
  description = "Deployment environment tag."
  type        = string
  default     = "production"
}

variable "vpc_cidr" {
  description = "CIDR block for the StartTech VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Optional explicit availability zones; the first two available zones are used by default."
  type        = list(string)
  default     = []
}

variable "cluster_version" {
  description = "Amazon EKS Kubernetes version."
  type        = string
  default     = "1.34"
}

variable "node_instance_types" {
  description = "Managed node group EC2 instance types."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "desired_nodes" {
  type    = number
  default = 2
}

variable "minimum_nodes" {
  type    = number
  default = 2
}

variable "maximum_nodes" {
  type    = number
  default = 4
}

variable "github_owner" {
  description = "GitHub account allowed to assume the deployment roles."
  type        = string
  default     = "adedokuntoluwanimi"
}

variable "infrastructure_repository" {
  type    = string
  default = "starttech-infra"
}

variable "application_repository" {
  type    = string
  default = "starttech-application"
}

variable "additional_tags" {
  description = "Extra tags merged into every supported resource."
  type        = map(string)
  default     = {}
}

variable "vpc_cidr" {
  description = "CIDR block for the StartTech VPC."
  type        = string
}

variable "availability_zones" {
  description = "Two availability zones used by every subnet tier."
  type        = list(string)

  validation {
    condition     = length(var.availability_zones) >= 2
    error_message = "At least two availability zones are required."
  }
}

variable "cluster_name" {
  description = "EKS cluster name used for Kubernetes subnet discovery tags."
  type        = string
}

variable "tags" {
  description = "Tags applied to networking resources."
  type        = map(string)
  default     = {}
}

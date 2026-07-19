variable "vpc_id" {
  type = string
}

variable "database_subnet_ids" {
  type = list(string)
}

variable "eks_worker_security_group_id" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}

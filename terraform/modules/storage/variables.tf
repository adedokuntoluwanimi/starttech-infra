variable "frontend_bucket_name" {
  type = string
}

variable "ecr_repository_name" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}

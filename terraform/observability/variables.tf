variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "tf_state_bucket" {
  type    = string
  default = "project-3-tfstate-273517699789-us-east-1"
}

variable "project_name" {
  type    = string
  default = "project-3-secure-cicd-pipeline"
}

variable "notification_email" {
  description = "Email subscribed to scan finding messages; empty disables email subscription."
  type        = string
  default     = ""
}

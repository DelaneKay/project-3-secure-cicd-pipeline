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

variable "juice_shop_instance_type" {
  type    = string
  default = "t3.small"
}

variable "runner_instance_type" {
  type    = string
  default = "t3.small"
}

variable "runner_registration_token_parameter" {
  description = "SSM SecureString parameter holding a fresh GitHub runner registration token."
  type        = string
  default     = "/project-3/github-runner/registration-token"
}

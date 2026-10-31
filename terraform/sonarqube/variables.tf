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
variable "sonarqube_instance_type" {
  description = "Instance size for the private SonarQube host."
  type        = string
  default     = "c7i-flex.large"
}
variable "sonarqube_db_name" {
  type    = string
  default = "sonarqube"
}

variable "aws_region" {
  description = "AWS Region for the Project 3 lab."
  type        = string
  default     = "us-east-1"
}
variable "tf_state_bucket" {
  description = "Private S3 bucket used by the independently managed Terraform states."
  type        = string
  default     = "project-3-tfstate-273517699789-us-east-1"
}
variable "project_name" {
  description = "Project identifier used for resource names and tags."
  type        = string
  default     = "project-3-secure-cicd-pipeline"
}
variable "db_identifier" {
  description = "Unique identifier for the SonarQube RDS instance."
  type        = string
  default     = "project-3-sonarqube"
}
variable "db_name" {
  description = "Initial PostgreSQL database name for SonarQube."
  type        = string
  default     = "sonarqube"
}
variable "db_master_username" {
  description = "Database username managed by RDS."
  type        = string
  default     = "sonarqube_admin"
}
variable "db_engine_version" {
  description = "PostgreSQL engine version selected for this lab."
  type        = string
  default     = "17.11"
}
variable "db_instance_class" {
  description = "RDS instance class selected for this lab."
  type        = string
  default     = "db.t4g.micro"
}

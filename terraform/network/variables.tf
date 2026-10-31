variable "aws_region" {
  description = "AWS Region for the Project 3 lab."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project identifier used for resource names and tags."
  type        = string
  default     = "project-3-secure-cicd-pipeline"
}

variable "vpc_cidr" {
  description = "CIDR range for the isolated Project 3 VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "availability_zones" {
  description = "Two Availability Zones used by the lab subnets."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "public_subnet_cidrs" {
  description = "CIDR ranges for the public Juice Shop and runner subnets."
  type        = list(string)
  default     = ["10.20.1.0/24", "10.20.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR ranges for private SonarQube and database subnets."
  type        = list(string)
  default     = ["10.20.11.0/24", "10.20.12.0/24"]
}

variable "juice_shop_allowed_cidrs" {
  description = "Public IPv4 CIDR ranges allowed to access Juice Shop on TCP 3000. Keep this restricted to trusted lab users."
  type        = list(string)
  default     = []
}

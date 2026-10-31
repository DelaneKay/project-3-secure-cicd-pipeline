resource "aws_vpc" "lab" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  instance_tenancy     = "default"

  tags = {
    Name        = "${var.project_name}-vpc"
    Project     = var.project_name
    Environment = "lab"
    ManagedBy   = "Terraform"
  }
}

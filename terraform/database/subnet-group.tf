resource "aws_db_subnet_group" "sonarqube" {
  name        = "${var.db_identifier}-subnets"
  description = "Private subnets for the Project 3 SonarQube database."

  subnet_ids = data.terraform_remote_state.network.outputs.private_subnet_ids

  tags = {
    Name        = "${var.db_identifier}-subnets"
    Project     = var.project_name
    Environment = "lab"
    ManagedBy   = "Terraform"
  }
}

resource "aws_db_instance" "sonarqube" {
  identifier = var.db_identifier

  engine         = "postgres"
  engine_version = var.db_engine_version
  instance_class = var.db_instance_class

  db_name  = var.db_name
  username = var.db_master_username
  port     = 5432

  manage_master_user_password = true

  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true

  db_subnet_group_name = aws_db_subnet_group.sonarqube.name
  vpc_security_group_ids = [
    data.terraform_remote_state.network.outputs.database_security_group_id
  ]
  publicly_accessible = false

  multi_az                   = false
  backup_retention_period    = 0
  auto_minor_version_upgrade = true

  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  deletion_protection   = false
  skip_final_snapshot   = true
  copy_tags_to_snapshot = true

  tags = {
    Name        = var.db_identifier
    Project     = var.project_name
    Environment = "lab"
    ManagedBy   = "Terraform"
  }
}

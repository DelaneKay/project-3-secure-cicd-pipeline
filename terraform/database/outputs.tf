output "db_instance_identifier" {
  description = "Identifier of the SonarQube PostgreSQL instance."
  value       = aws_db_instance.sonarqube.identifier
}

output "db_address" {
  description = "Private endpoint hostname for the SonarQube PostgreSQL instance."
  value       = aws_db_instance.sonarqube.address
}

output "db_port" {
  description = "Port used by the SonarQube PostgreSQL instance."
  value       = aws_db_instance.sonarqube.port
}

output "db_name" {
  description = "Database name created for SonarQube."
  value       = aws_db_instance.sonarqube.db_name
}

output "master_user_secret_arn" {
  description = "Secrets Manager ARN for the RDS-managed database credentials."
  value       = aws_db_instance.sonarqube.master_user_secret[0].secret_arn
}

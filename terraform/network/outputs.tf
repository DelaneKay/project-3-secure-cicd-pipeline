output "vpc_id" {
  description = "ID of the Project 3 VPC."
  value       = aws_vpc.lab.id
}

output "vpc_cidr_block" {
  description = "CIDR block of the Project 3 VPC."
  value       = aws_vpc.lab.cidr_block
}

output "public_subnet_ids" {
  description = "IDs of public subnets for Juice Shop and the self-hosted runner."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of private subnets for SonarQube and the database."
  value       = aws_subnet.private[*].id
}

output "vpc_endpoint_security_group_id" {
  description = "Security group attached to interface endpoints."
  value       = aws_security_group.vpc_endpoints.id
}

output "interface_vpc_endpoint_ids" {
  description = "IDs of the Systems Manager and CloudWatch Logs interface endpoints."
  value       = { for service, endpoint in aws_vpc_endpoint.interface : service => endpoint.id }
}

output "juice_shop_security_group_id" {
  description = "Security group for the Juice Shop host."
  value       = aws_security_group.juice_shop.id
}

output "github_runner_security_group_id" {
  description = "Security group for the self-hosted GitHub Actions runner."
  value       = aws_security_group.github_runner.id
}

output "sonarqube_security_group_id" {
  description = "Security group for the private SonarQube host."
  value       = aws_security_group.sonarqube.id
}

output "database_security_group_id" {
  description = "Security group for the private RDS database."
  value       = aws_security_group.database.id
}

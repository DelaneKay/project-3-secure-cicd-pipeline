resource "aws_security_group" "packer_builder" {
  name_prefix = "${var.project_name}-packer-builder-"
  description = "Temporary Packer AMI builders: no inbound access; HTTP and HTTPS egress only."
  vpc_id      = aws_vpc.lab.id

  egress {
    description = "HTTP for package mirrors during image builds."
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "HTTPS for SSM, AWS APIs, and build downloads."
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-packer-builder-sg"
    Project     = var.project_name
    Environment = "lab"
    ManagedBy   = "Terraform"
    Purpose     = "temporary-packer-builder"
  }
}

output "packer_builder_security_group_id" {
  description = "Security group for temporary Packer AMI builders."
  value       = aws_security_group.packer_builder.id
}

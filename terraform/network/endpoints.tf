locals {
  endpoint_client_cidrs = concat(var.private_subnet_cidrs, var.public_subnet_cidrs)
}

resource "aws_security_group" "vpc_endpoints" {
  name_prefix = "${var.project_name}-vpc-endpoints-"
  description = "Allow lab instances to reach AWS interface endpoints over HTTPS."
  vpc_id      = aws_vpc.lab.id

  dynamic "ingress" {
    for_each = local.endpoint_client_cidrs
    content {
      description = "HTTPS from lab subnet ${ingress.value}"
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
    }
  }

  tags = {
    Name        = "${var.project_name}-vpc-endpoints-sg"
    Project     = var.project_name
    Environment = "lab"
    ManagedBy   = "Terraform"
  }
}

locals {
  interface_endpoint_services = toset(["ssm", "ssmmessages", "ec2messages", "logs", "secretsmanager"])
}

resource "aws_vpc_endpoint" "interface" {
  for_each            = local.interface_endpoint_services
  vpc_id              = aws_vpc.lab.id
  service_name        = "com.amazonaws.${var.aws_region}.${each.value}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    Name        = "${var.project_name}-${each.value}-endpoint"
    Project     = var.project_name
    Environment = "lab"
    ManagedBy   = "Terraform"
  }
}

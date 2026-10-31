resource "aws_security_group" "juice_shop" {
  name_prefix = "${var.project_name}-juice-shop-"
  description = "Juice Shop access for trusted lab users and the scanner runner."
  vpc_id      = aws_vpc.lab.id

  egress {
    description = "HTTPS for SSM and CloudWatch agent communication."
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-juice-shop-sg"
    Project     = var.project_name
    Environment = "lab"
    ManagedBy   = "Terraform"
  }
}

resource "aws_security_group" "github_runner" {
  name_prefix = "${var.project_name}-github-runner-"
  description = "Outbound-only GitHub Actions runner with access to the lab scan targets."
  vpc_id      = aws_vpc.lab.id

  egress {
    description = "HTTPS for GitHub Actions, AWS APIs, SSM, and CloudWatch."
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description     = "ZAP access to Juice Shop."
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.juice_shop.id]
  }

  egress {
    description     = "SonarScanner access to private SonarQube."
    from_port       = 9000
    to_port         = 9000
    protocol        = "tcp"
    security_groups = [aws_security_group.sonarqube.id]
  }

  tags = {
    Name        = "${var.project_name}-github-runner-sg"
    Project     = var.project_name
    Environment = "lab"
    ManagedBy   = "Terraform"
  }
}

resource "aws_security_group" "sonarqube" {
  name_prefix = "${var.project_name}-sonarqube-"
  description = "Private SonarQube access from the self-hosted runner."
  vpc_id      = aws_vpc.lab.id

  egress {
    description     = "HTTPS to SSM and CloudWatch interface endpoints."
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.vpc_endpoints.id]
  }

  egress {
    description     = "PostgreSQL connection to the SonarQube database."
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.database.id]
  }

  tags = {
    Name        = "${var.project_name}-sonarqube-sg"
    Project     = var.project_name
    Environment = "lab"
    ManagedBy   = "Terraform"
  }
}

resource "aws_security_group" "database" {
  name_prefix = "${var.project_name}-database-"
  description = "RDS access only from the SonarQube host."
  vpc_id      = aws_vpc.lab.id

  tags = {
    Name        = "${var.project_name}-database-sg"
    Project     = var.project_name
    Environment = "lab"
    ManagedBy   = "Terraform"
  }
}

resource "aws_vpc_security_group_ingress_rule" "juice_shop_lab_users" {
  for_each = toset(var.juice_shop_allowed_cidrs)

  security_group_id = aws_security_group.juice_shop.id
  description       = "Juice Shop access from an approved lab-user CIDR."
  cidr_ipv4         = each.value
  from_port         = 3000
  to_port           = 3000
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "juice_shop_runner" {
  security_group_id            = aws_security_group.juice_shop.id
  description                  = "ZAP access from the self-hosted runner."
  referenced_security_group_id = aws_security_group.github_runner.id
  from_port                    = 3000
  to_port                      = 3000
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "sonarqube_runner" {
  security_group_id            = aws_security_group.sonarqube.id
  description                  = "SonarScanner access from the self-hosted runner."
  referenced_security_group_id = aws_security_group.github_runner.id
  from_port                    = 9000
  to_port                      = 9000
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "database_sonarqube" {
  security_group_id            = aws_security_group.database.id
  description                  = "PostgreSQL access from SonarQube only."
  referenced_security_group_id = aws_security_group.sonarqube.id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
}

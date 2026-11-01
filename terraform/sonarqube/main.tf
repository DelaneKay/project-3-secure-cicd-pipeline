data "aws_iam_policy_document" "ec2_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "sonarqube" {
  name               = "${var.project_name}-sonarqube"
  assume_role_policy = data.aws_iam_policy_document.ec2_trust.json

  tags = {
    Project     = var.project_name
    Environment = "lab"
    ManagedBy   = "Terraform"
  }
}

resource "aws_iam_role_policy_attachment" "sonarqube_ssm" {
  role       = aws_iam_role.sonarqube.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "sonarqube_runtime" {
  name = "sonarqube-runtime"
  role = aws_iam_role.sonarqube.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = data.terraform_remote_state.database.outputs.master_user_secret_arn
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:DescribeLogStreams", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/project-3/sonarqube:*"
      },
      {
        Effect   = "Allow"
        Action   = ["cloudwatch:PutMetricData"]
        Resource = "*"
        Condition = {
          StringEquals = {
            "cloudwatch:namespace" = "Project3/SonarQube"
          }
        }
      }
    ]
  })
}

resource "aws_iam_instance_profile" "sonarqube" {
  name = "${var.project_name}-sonarqube"
  role = aws_iam_role.sonarqube.name
}

resource "aws_instance" "sonarqube" {
  ami                    = data.aws_ami.sonarqube.id
  instance_type          = var.sonarqube_instance_type
  subnet_id              = data.terraform_remote_state.network.outputs.private_subnet_ids[0]
  vpc_security_group_ids = [data.terraform_remote_state.network.outputs.sonarqube_security_group_id]
  iam_instance_profile   = aws_iam_instance_profile.sonarqube.name

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }

  root_block_device {
    encrypted             = true
    volume_type           = "gp3"
    volume_size           = 30
    delete_on_termination = true
  }

  tags = {
    Name                      = "${var.project_name}-sonarqube"
    Project                   = var.project_name
    Environment               = "lab"
    ManagedBy                 = "Terraform"
    Image                     = "sonarqube"
    "sonarqube-db-host"       = data.terraform_remote_state.database.outputs.db_address
    "sonarqube-db-port"       = tostring(data.terraform_remote_state.database.outputs.db_port)
    "sonarqube-db-name"       = var.sonarqube_db_name
    "sonarqube-db-secret-arn" = data.terraform_remote_state.database.outputs.master_user_secret_arn
  }

  depends_on = [aws_iam_role_policy.sonarqube_runtime]
}

output "sonarqube_instance_id" {
  description = "EC2 instance ID running private SonarQube."
  value       = aws_instance.sonarqube.id
}

output "sonarqube_private_ip" {
  description = "Private IP of the SonarQube host."
  value       = aws_instance.sonarqube.private_ip
}

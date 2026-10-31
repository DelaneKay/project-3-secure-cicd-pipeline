locals {
  common_tags = {
    Project     = var.project_name
    Environment = "lab"
    ManagedBy   = "Terraform"
  }

  cw_log_arns = [
    for name in [
      "/project-3/juice-shop/syslog",
      "/project-3/juice-shop/auth",
      "/project-3/juice-shop/app",
      "/project-3/github-runner",
      "/project-3/pipeline/scans",
    ] :
    "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:${name}:*"
  ]
}

data "aws_iam_policy_document" "ec2_trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "juice_shop" {
  name               = "${var.project_name}-juice-shop"
  assume_role_policy = data.aws_iam_policy_document.ec2_trust.json
  tags               = local.common_tags
}

resource "aws_iam_role" "github_runner" {
  name               = "${var.project_name}-github-runner"
  assume_role_policy = data.aws_iam_policy_document.ec2_trust.json
  tags               = local.common_tags
}

resource "aws_iam_role_policy_attachment" "juice_shop_ssm" {
  role       = aws_iam_role.juice_shop.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "runner_ssm" {
  role       = aws_iam_role.github_runner.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "juice_shop_logs" {
  name = "cloudwatch-logs"
  role = aws_iam_role.juice_shop.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:DescribeLogStreams", "logs:PutLogEvents"]
        Resource = slice(local.cw_log_arns, 0, 3)
      },
      {
        Effect   = "Allow"
        Action   = ["cloudwatch:PutMetricData"]
        Resource = "*"
        Condition = {
          StringEquals = {
            "cloudwatch:namespace" = "Project3/JuiceShop"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "runner_runtime" {
  name = "scanner-runtime"
  role = aws_iam_role.github_runner.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:DescribeLogStreams", "logs:PutLogEvents"]
        Resource = slice(local.cw_log_arns, 3, 5)
      },
      {
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = data.terraform_remote_state.observability.outputs.scan_findings_topic_arn
      },
      {
        Effect   = "Allow"
        Action   = ["ssm:GetParameter", "ssm:DeleteParameter"]
        Resource = "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter${var.runner_registration_token_parameter}"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "juice_shop" {
  name = "${var.project_name}-juice-shop"
  role = aws_iam_role.juice_shop.name
}

resource "aws_iam_instance_profile" "github_runner" {
  name = "${var.project_name}-github-runner"
  role = aws_iam_role.github_runner.name
}

locals {
  log_groups = {
    "/project-3/juice-shop/syslog" = 14
    "/project-3/juice-shop/auth"   = 14
    "/project-3/juice-shop/app"    = 14
    "/project-3/sonarqube"         = 14
    "/project-3/github-runner"     = 14
    "/project-3/pipeline/scans"    = 30
  }

  common_tags = {
    Project     = var.project_name
    Environment = "lab"
    ManagedBy   = "Terraform"
  }
}

resource "aws_cloudwatch_log_group" "project" {
  for_each          = local.log_groups
  name              = each.key
  retention_in_days = each.value
  tags              = local.common_tags
}

resource "aws_sns_topic" "scan_findings" {
  name              = "${var.project_name}-scan-findings"
  kms_master_key_id = "alias/aws/sns"
  tags              = local.common_tags
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.notification_email == "" ? 0 : 1
  topic_arn = aws_sns_topic.scan_findings.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

output "scan_findings_topic_arn" {
  description = "SNS topic for concise scan findings messages."
  value       = aws_sns_topic.scan_findings.arn
}

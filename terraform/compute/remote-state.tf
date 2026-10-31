data "terraform_remote_state" "network" {
  backend = "s3"

  config = {
    bucket = var.tf_state_bucket
    key    = "project-3/network/terraform.tfstate"
    region = var.aws_region
  }
}

data "terraform_remote_state" "observability" {
  backend = "s3"

  config = {
    bucket = var.tf_state_bucket
    key    = "project-3/observability/terraform.tfstate"
    region = var.aws_region
  }
}

data "aws_caller_identity" "current" {}

data "aws_ami" "juice_shop" {
  most_recent = true
  owners      = ["self"]

  filter {
    name   = "tag:Project"
    values = [var.project_name]
  }

  filter {
    name   = "tag:Image"
    values = ["juice-shop"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

data "aws_ami" "github_runner" {
  most_recent = true
  owners      = ["self"]

  filter {
    name   = "tag:Project"
    values = [var.project_name]
  }

  filter {
    name   = "tag:Image"
    values = ["github-runner"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

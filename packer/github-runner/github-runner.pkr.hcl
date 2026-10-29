packer {
  required_plugins {
    amazon = {
      source  = "github.com/hashicorp/amazon"
      version = ">= 1.8.3, < 1.9.0"
    }
  }
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "source_ami_id" {
  type    = string
  default = "ami-0d6dd9e8265d48906"
}

variable "subnet_id" {
  type    = string
  default = "subnet-0553c27c63a86071e"
}

variable "security_group_id" {
  type    = string
  default = "sg-0ffe04fab57d2125b"
}

variable "builder_instance_profile" {
  type    = string
  default = "project-3-packer-builder-profile"
}

variable "builder_instance_type" {
  type    = string
  default = "t3.small"
}

variable "github_runner_version" {
  type = string
}

variable "gitleaks_version" {
  type = string
}

variable "sonar_scanner_version" {
  type = string
}

variable "dependency_check_version" {
  type = string
}

variable "zap_version" {
  type = string
}

variable "terraform_version" {
  type = string
}

variable "aws_cli_version" {
  type = string
}

variable "java_package" {
  type = string
}

source "amazon-ebs" "github_runner" {
  region                      = var.aws_region
  source_ami                  = var.source_ami_id
  instance_type               = var.builder_instance_type
  subnet_id                   = var.subnet_id
  security_group_id           = var.security_group_id
  associate_public_ip_address = true

  iam_instance_profile = var.builder_instance_profile
  communicator         = "ssh"
  ssh_interface        = "session_manager"
  ssh_username         = "ubuntu"
  ssh_timeout          = "30m"
  ssh_clear_authorized_keys = true

  ami_name        = "project-3-github-runner-ubuntu-24-04-{{timestamp}}"
  ami_description = "Hardened Ubuntu 24.04 AMI with unregistered Project 3 GitHub Actions runner and security tools"

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  launch_block_device_mappings {
    device_name           = "/dev/sda1"
    volume_size           = 25
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  run_tags = {
    Project = "project-3-secure-cicd-pipeline"
    Purpose = "temporary-packer-builder"
  }

  tags = {
    Project = "project-3-secure-cicd-pipeline"
    Image   = "github-runner"
    OS      = "ubuntu-24.04"
  }
}

build {
  name    = "github-runner-ami"
  sources = ["source.amazon-ebs.github_runner"]

  provisioner "shell" {
    script = "${path.root}/scripts/install-runner.sh"

    environment_vars = [
      "GITHUB_RUNNER_VERSION=${var.github_runner_version}",
      "GITLEAKS_VERSION=${var.gitleaks_version}",
      "SONAR_SCANNER_VERSION=${var.sonar_scanner_version}",
      "DEPENDENCY_CHECK_VERSION=${var.dependency_check_version}",
      "ZAP_VERSION=${var.zap_version}",
      "TERRAFORM_VERSION=${var.terraform_version}",
      "AWS_CLI_VERSION=${var.aws_cli_version}",
      "JAVA_PACKAGE=${var.java_package}"
    ]

    execute_command = "sudo -E env {{ .Vars }} bash '{{ .Path }}'"
  }
}

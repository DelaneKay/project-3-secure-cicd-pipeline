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
  type = string
}

variable "subnet_id" {
  type = string
}

variable "security_group_id" {
  type = string
}

variable "builder_instance_profile" {
  type    = string
  default = "project-3-packer-builder-profile"
}

variable "builder_instance_type" {
  type    = string
  default = "t3.small"
}

source "amazon-ebs" "juice_shop" {
  region                      = var.aws_region
  source_ami                  = var.source_ami_id
  instance_type               = var.builder_instance_type
  subnet_id                   = var.subnet_id
  security_group_id           = var.security_group_id
  associate_public_ip_address = true

  iam_instance_profile      = var.builder_instance_profile
  communicator              = "ssh"
  ssh_interface             = "session_manager"
  ssh_username              = "ubuntu"
  ssh_timeout               = "30m"
  ssh_clear_authorized_keys = true

  ami_name        = "project-3-juice-shop-ubuntu-24-04-{{timestamp}}"
  ami_description = "Hardened Ubuntu 24.04 AMI with OWASP Juice Shop for Project 3"

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  run_tags = {
    Project = "project-3-secure-cicd-pipeline"
    Purpose = "temporary-packer-builder"
  }

  tags = {
    Project = "project-3-secure-cicd-pipeline"
    Image   = "juice-shop"
    OS      = "ubuntu-24.04"
  }
}

build {
  name    = "juice-shop-ami"
  sources = ["source.amazon-ebs.juice_shop"]

  provisioner "shell" {
    script          = "${path.root}/scripts/install-juice-shop.sh"
    execute_command = "sudo -E bash '{{ .Path }}'"
  }
}

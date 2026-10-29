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

variable "sonarqube_version" {
  type = string
}

variable "java_package" {
  type = string
}

source "amazon-ebs" "sonarqube" {
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

  ami_name        = "project-3-sonarqube-ubuntu-24-04-{{timestamp}}"
  ami_description = "Hardened Ubuntu 24.04 AMI with SonarQube Community Build for Project 3"

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  launch_block_device_mappings {
    device_name           = "/dev/sda1"
    volume_size           = 30
    volume_type           = "gp3"
    delete_on_termination = true
  }

  run_tags = {
    Project = "project-3-secure-cicd-pipeline"
    Purpose = "temporary-packer-builder"
  }

  tags = {
    Project = "project-3-secure-cicd-pipeline"
    Image   = "sonarqube"
    OS      = "ubuntu-24.04"
  }
}

build {
  name    = "sonarqube-ami"
  sources = ["source.amazon-ebs.sonarqube"]

  provisioner "shell" {
    script = "${path.root}/scripts/install-sonarqube.sh"

    environment_vars = [
      "SONARQUBE_VERSION=${var.sonarqube_version}",
      "JAVA_PACKAGE=${var.java_package}",
    ]

    execute_command = "sudo -E env {{ .Vars }} bash '{{ .Path }}'"
  }
  provisioner "shell" {
    script          = "${path.root}/scripts/install-cloudwatch-agent.sh"
    execute_command = "sudo -E bash '{{ .Path }}'"
  }

}

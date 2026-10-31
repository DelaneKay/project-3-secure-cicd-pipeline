resource "aws_instance" "juice_shop" {
  ami                         = data.aws_ami.juice_shop.id
  instance_type               = var.juice_shop_instance_type
  subnet_id                   = data.terraform_remote_state.network.outputs.public_subnet_ids[0]
  vpc_security_group_ids      = [data.terraform_remote_state.network.outputs.juice_shop_security_group_id]
  iam_instance_profile        = aws_iam_instance_profile.juice_shop.name
  associate_public_ip_address = true

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    encrypted             = true
    volume_type           = "gp3"
    volume_size           = 16
    delete_on_termination = true
  }

  tags = merge(local.common_tags, {
    Name  = "${var.project_name}-juice-shop"
    Image = "juice-shop"
  })
}

resource "aws_instance" "github_runner" {
  ami                         = data.aws_ami.github_runner.id
  instance_type               = var.runner_instance_type
  subnet_id                   = data.terraform_remote_state.network.outputs.public_subnet_ids[0]
  vpc_security_group_ids      = [data.terraform_remote_state.network.outputs.github_runner_security_group_id]
  iam_instance_profile        = aws_iam_instance_profile.github_runner.name
  associate_public_ip_address = true

  user_data = templatefile("${path.module}/runner-user-data.sh.tftpl", {
    aws_region                   = var.aws_region
    registration_token_parameter = var.runner_registration_token_parameter
    repository_url               = "https://github.com/DelaneKay/project-3-secure-cicd-pipeline"
  })
  user_data_replace_on_change = true

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    encrypted             = true
    volume_type           = "gp3"
    volume_size           = 25
    delete_on_termination = true
  }

  tags = merge(local.common_tags, {
    Name  = "${var.project_name}-scanner-runner"
    Image = "github-runner"
  })
}

output "juice_shop_instance_id" {
  description = "EC2 instance ID running OWASP Juice Shop."
  value       = aws_instance.juice_shop.id
}

output "juice_shop_public_ip" {
  description = "Public IP for restricted lab access to Juice Shop."
  value       = aws_instance.juice_shop.public_ip
}

output "github_runner_instance_id" {
  description = "EC2 instance ID running the self-hosted scanner runner."
  value       = aws_instance.github_runner.id
}

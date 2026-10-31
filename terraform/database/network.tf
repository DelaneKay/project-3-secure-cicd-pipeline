data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket = var.tf_state_bucket
    key    = "project-3/network/terraform.tfstate"
    region = var.aws_region
  }
}

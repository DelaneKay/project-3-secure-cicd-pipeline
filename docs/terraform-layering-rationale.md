# Terraform Layering Rationale

## Decision

Project 3 keeps independently deployable Terraform roots. Each directory has its own configuration and S3 state key, allowing CI to plan and apply each layer separately while retaining dependency order.

- `terraform/network/` - VPC, subnets, routes, and VPC endpoints
- `terraform/database/` - RDS PostgreSQL
- `terraform/observability/` - CloudWatch log groups and SNS notifications
- `terraform/compute/` - Juice Shop and self-hosted scanner runner EC2 instances and instance roles
- `terraform/sonarqube/` - private SonarQube EC2 instance and runtime role

The deployment workflow runs network first; database and observability run after network and may run in parallel; compute follows network and observability; SonarQube follows network, database, and observability.

## Why use layers

- Smaller plans focus review on one infrastructure area.
- Changes to one layer are less likely to affect unrelated resources.
- Layers have separate lifecycles and make troubleshooting clearer.
- Explicit remote-state outputs show dependencies between layers.
- CI can run independent layers in parallel after prerequisites complete.

## State and operating notes

Each root stores state in the private, versioned S3 bucket created by the one-time bootstrap script. State keys are separate, and the S3 backend native lock file prevents two Terraform operations from changing the same root at once. GitHub workflow concurrency serializes deployments across roots.

The bootstrap bucket is separate from the five Terraform states and survives Terraform destroy. After the lab is fully destroyed, delete all object versions and lock objects in the bucket, then delete the bucket to stop state-storage charges.

Terraform plan and apply run through GitHub Actions. Pull-request validation has no AWS credentials. Merged changes create reviewable saved plans; a protected environment approval gates applying each saved plan.

Destroy layers in reverse dependency order. RDS snapshots, AMIs and backing snapshots, runner registration, bootstrap IAM roles, and the S3 state bucket have lifecycles outside the corresponding Terraform root and require explicit cleanup.

# GitHub Actions Terraform setup

GitHub-hosted runners are used only for Terraform. Application and security scanning jobs remain on the separate self-hosted scanner EC2 runner.

## Workflow behavior

- Pull requests run formatting, init without a backend, validation, Gitleaks, and Checkov. They receive no AWS credentials and cannot deploy.
- A merge to `master` changing Terraform or its workflows starts deployment.
- The workflow applies five independent roots. Network runs first. Database and observability run in parallel after network. Compute waits for network and observability. SonarQube waits for network, database, and observability.
- Each root has its own S3 state key and native `.tflock` object.
- The workflow uploads a saved binary plan and readable text plan. Each apply waits for approval in the protected `terraform-lab-apply` environment and applies that exact plan.
- Workflow-level concurrency prevents overlapping deployment runs. S3 locks protect each individual state.
- First deployment works because a dependent root is planned only after its upstream roots have applied and stored outputs.
- Gitleaks and Checkov findings are report-only. Terraform format/validation errors and scanner execution failures still fail the workflow.

## One-time S3 state bootstrap

The state bucket must exist before the first workflow can initialize. It is a bootstrap prerequisite, not a Terraform layer. From WSL, with the `mds-devsecops-lab` AWS CLI profile authenticated, run this only when ready to bootstrap:

```bash
cd ~/projects/project-3-secure-cicd-pipeline
AWS_PROFILE=mds-devsecops-lab AWS_REGION=us-east-1 ./scripts/bootstrap-terraform-state.sh
```

The script creates/configures a private, versioned, encrypted bucket with public access blocked, bucket-owner enforcement, and a policy denying insecure transport. Default bucket name for account `273517699789`: `project-3-tfstate-273517699789-us-east-1`. It creates no compute resources.

| Root | S3 state key |
| --- | --- |
| network | project-3/network/terraform.tfstate |
| database | project-3/database/terraform.tfstate |
| observability | project-3/observability/terraform.tfstate |
| compute | project-3/compute/terraform.tfstate |
| sonarqube | project-3/sonarqube/terraform.tfstate |

## AWS OIDC setup

Create the GitHub OIDC provider in account `273517699789`: issuer `https://token.actions.githubusercontent.com`, audience `sts.amazonaws.com`. Use separate plan and apply roles; do not store AWS keys in GitHub.

- Plan role trust: audience is `sts.amazonaws.com`; subject is `repo:DelaneKay/project-3-secure-cicd-pipeline:ref:refs/heads/master`.
- Apply role trust: audience is `sts.amazonaws.com`; subject is `repo:DelaneKay/project-3-secure-cicd-pipeline:environment:terraform-lab-apply`.

Give the plan role read-only access to the managed AWS services and state objects, plus S3 write/delete access only to the five state lock paths. Give the apply role only the actions represented by these Terraform roots, state read/write, lock read/write/delete, and `iam:PassRole` restricted to Project 3 instance roles with EC2 as the receiving service. Restrict S3 ListBucket to `project-3/*`. Do not attach `AdministratorAccess`.

Add these repository Actions variables:

- `TF_STATE_BUCKET`: `project-3-tfstate-273517699789-us-east-1`
- `AWS_TERRAFORM_PLAN_ROLE_ARN`: plan role ARN
- `AWS_TERRAFORM_APPLY_ROLE_ARN`: apply role ARN
- `JUICE_SHOP_ALLOWED_CIDRS`: JSON list of trusted client CIDRs, ideally your current public IP with `/32`. The default is empty, so public clients cannot reach port 3000 until set.
- `TF_NOTIFICATION_EMAIL`: optional email for the SNS subscription. Confirm the AWS subscription message.

Configure GitHub environment `terraform-lab-apply` with required reviewers and deployment branch `master`. Review the text plan artifact before approving its apply job. Binary plans are retained for one day in the private repository; they can contain sensitive infrastructure values.

## Runner registration

The compute layer does not put a runner token in Terraform state, user data, or an AMI. Immediately before compute apply, the workflow should create a short-lived repository registration token using a dedicated GitHub App with only repository **Administration: write**, then save it as an SSM SecureString at `/project-3/github-runner/registration-token`. The runner instance role can read and delete only that parameter. The runner consumes it at first boot.

Store `RUNNER_GITHUB_APP_ID` and `RUNNER_GITHUB_APP_PRIVATE_KEY` as protected Actions secrets. The compute reusable workflow receives only those two named secrets. The apply role's `ssm:PutParameter` permission must cover only this one parameter. Run scanner workflows on the self-hosted runner only for trusted, merged code; do not execute untrusted pull request code on it.

## Cleanup

Before starting `Terraform destroy`, manually create and verify the RDS snapshot if you want a backup. The repository's manually triggered destroy workflow asks for the word `DESTROY`, creates reviewable destroy plans, and applies them only after environment approval in reverse dependency order. It destroys the RDS instance with final snapshots disabled, so create any desired snapshot first. The state bucket remains after Terraform destroy because Terraform needs its backend during teardown. S3 charges continue for stored current and noncurrent object versions. After all lab roots are destroyed, delete all object versions and lock objects, then delete the bucket. Terraform destroy does not remove the bootstrap bucket.

# Packer IAM Bootstrap

Packer uses two distinct IAM roles before Terraform has deployed the lab IAM resources:

1. `project-3-packer-operator-role` is assumed by the local Packer process in WSL. It grants narrowly scoped permissions to build and clean up AMIs.
2. `project-3-packer-builder-role` is attached to the temporary EC2 builder through `project-3-packer-builder-profile`. It grants the builder SSM managed-instance permissions only.

The operator role is not attached to EC2, and the builder role does not authorize the local Packer process.

## What this creates

- IAM role: `project-3-packer-operator-role` (assumed by the local Packer process)
- IAM role: `project-3-packer-builder-role` (attached to temporary EC2 builder)
- IAM instance profile: `project-3-packer-builder-profile`
- AWS-managed policy attached to the builder role: `AmazonSSMManagedInstanceCore`
- A narrowly scoped Packer operator policy, including `iam:PassRole` only for the builder role and EC2 as the receiving service

The builder role is for temporary Packer build instances only. It is not the runtime role for Juice Shop, SonarQube, or the GitHub Actions runner. The operator role is used by the local Packer process and is separate. IAM roles and profiles do not create EC2 instances or have compute charges. Remove both roles and the builder instance profile during final lab cleanup, after all image builds are complete.

## Prerequisites

- AWS CLI is authenticated as the `mds-devsecops-lab` IAM user using short-lived `aws login` credentials.
- AWS region for this lab is `us-east-1`.
- The IAM user must be allowed to assume `project-3-packer-operator-role`; it should not receive direct Packer EC2 build permissions.
- The operator role must have only required Packer EC2 and SSM-session permissions. Its `iam:PassRole` permission must name only `project-3-packer-builder-role` and require EC2 as the receiving service.
- Configure a separate AWS CLI `credential_process` profile so Packer can consume the short-lived login session and assume the operator role. Do not put access keys in a file or environment variables.
- `session-manager-plugin` and Packer are installed in WSL.

Do not switch to root to bypass an `AccessDenied` response. Stop and ask an AWS administrator to grant or update the least-privilege permissions.

## Create the builder role and profile

Run in WSL using the `mds-devsecops-lab` profile. The trust policy lets EC2 assume the builder role. The attached AWS-managed policy gives the temporary builder the permissions needed for Systems Manager. This one-time bootstrap uses the IAM user session; Packer builds themselves use the operator role.

```bash
set -euo pipefail
umask 077

profile="mds-devsecops-lab"
role="project-3-packer-builder-role"
instance_profile="project-3-packer-builder-profile"
trust_file="$(mktemp)"
trap 'rm -f "$trust_file"' EXIT

aws sts get-caller-identity --profile "$profile" \
  --query Arn --output text

cat > "$trust_file" <<'JSON'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {"Service": "ec2.amazonaws.com"},
      "Action": "sts:AssumeRole"
    }
  ]
}
JSON

aws iam create-role \
  --role-name "$role" \
  --assume-role-policy-document "file://$trust_file" \
  --description "SSM access for temporary Project 3 Packer builders" \
  --profile "$profile"

aws iam attach-role-policy \
  --role-name "$role" \
  --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore \
  --profile "$profile"

aws iam create-instance-profile \
  --instance-profile-name "$instance_profile" \
  --profile "$profile"

aws iam add-role-to-instance-profile \
  --instance-profile-name "$instance_profile" \
  --role-name "$role" \
  --profile "$profile"

aws iam get-instance-profile \
  --instance-profile-name "$instance_profile" \
  --profile "$profile" \
  --query 'InstanceProfile.Roles[].RoleName' \
  --output text
```

Confirm that the identity ARN ends in `:user/mds-devsecops-lab` and the final output is `project-3-packer-builder-role`.

## Packer operator role and credential profile

Create `project-3-packer-operator-role` with a trust policy for the `mds-devsecops-lab` IAM user. Attach a least-privilege policy for Packer's EC2 build and cleanup actions, SSM session actions, and `iam:PassRole` limited to `project-3-packer-builder-role` for EC2. Do not attach `AmazonSSMManagedInstanceCore` to the operator role; that policy belongs only to the builder role.

Configure the AWS CLI login-backed source profile with `credential_process`, then configure a role profile that names the operator role and uses the source profile. Verify that `aws sts get-caller-identity` with the operator profile returns an assumed-role ARN before running Packer. Review the operator policy against the selected Packer builder options; do not give the operator `AdministratorAccess`.

These IAM create commands are intended to be run once. If a command fails after an earlier resource was created, stop and inspect the partial resources before retrying; do not blindly rerun the whole block.

## Packer connection note

The Packer Amazon EBS builder uses the local Session Manager plugin to tunnel its SSH communicator through SSM. This does not require an inbound SSH rule, an SSH key, or public port 22. Deployed lab instances remain administered through SSM without inbound SSH.

## Cleanup

After all Packer image builds are complete, remove the role and instance profile. If the role is still attached to the profile, remove it first, then delete the profile and role:

```bash
profile="mds-devsecops-lab"
role="project-3-packer-builder-role"
instance_profile="project-3-packer-builder-profile"
policy_arn="arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"

aws iam remove-role-from-instance-profile \
  --instance-profile-name "$instance_profile" \
  --role-name "$role" \
  --profile "$profile"

aws iam delete-instance-profile \
  --instance-profile-name "$instance_profile" \
  --profile "$profile"

aws iam detach-role-policy \
  --role-name "$role" \
  --policy-arn "$policy_arn" \
  --profile "$profile"

aws iam delete-role \
  --role-name "$role" \
  --profile "$profile"
```


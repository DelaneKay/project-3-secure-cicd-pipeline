# Packer Builder IAM Bootstrap

This guide creates the EC2 role and instance profile required for Packer's temporary AMI builder to register with AWS Systems Manager. It is a setup prerequisite before the first Packer image build, because Terraform has not yet deployed the lab IAM resources.

## What this creates

- IAM role: `project-3-packer-builder-role`
- IAM instance profile: `project-3-packer-builder-profile`
- AWS-managed policy attached to the role: `AmazonSSMManagedInstanceCore`

The role is for temporary Packer build instances only. It is not the runtime role for Juice Shop, SonarQube, or the GitHub Actions runner. It creates no EC2 instance and has no compute charge. Remove it and its instance profile during final lab cleanup, after all image builds are complete.

## Prerequisites

- AWS CLI is authenticated as the `mds-devsecops-lab` IAM user.
- AWS region for this lab is `us-east-1`.
- The IAM user must have narrowly scoped permission to create the role and instance profile, attach the SSM managed policy, add the role to the profile, and pass this role to EC2. Packer also needs the EC2 and SSM session permissions required to build and clean up AMIs.
- `session-manager-plugin` and Packer are installed in WSL.

Do not switch to root to bypass an `AccessDenied` response. Stop and ask an AWS administrator to grant the required least-privilege permissions. `iam:PassRole` should be restricted to `project-3-packer-builder-role` and to EC2 as the receiving service.

## Create the role and profile

Run in WSL. The trust policy lets EC2 assume this role. The attached AWS-managed policy gives the temporary builder the permissions needed for Systems Manager.

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

Confirm that the first ARN ends in `:user/mds-devsecops-lab` and the final output is `project-3-packer-builder-role`.

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


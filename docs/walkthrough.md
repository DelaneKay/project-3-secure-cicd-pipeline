# Project 3 — My step-by-step secure CI/CD lab walkthrough

> Repository copy: AWS account/resource identifiers, internal host addresses, database endpoints and personal email addresses have been replaced with placeholders. I obtain their real values using the lookup commands shown before running the dependent command. These placeholders are not literal working AWS IDs.

I documented the lab in the order I built and tested it, with the commands, expected results and troubleshooting needed to follow the work. I kept the deployment steps and scanner tests together so each change has a clear purpose.
**How to follow this:** the numbered steps are the successful path through the lab. The first Terraform deployment was manual; I later replaced routine local deployment with GitHub workflows. I use the corrected files from the repository when reproducing the final build.

**Where commands run:** unless I say otherwise, I run Bash in WSL as the Linux user `devsecops`, from `~/projects/project-3-secure-cicd-pipeline`. Commands inside a Packer provisioner run on its temporary AWS builder. SSM diagnostics execute on the explicitly selected AWS instance. A GitHub `run:` block executes on the runner selected by that job. I do not paste Bash into PowerShell.

**Historical values:** account `YOUR_ACCOUNT_ID`, region `us-east-1`, AMI IDs, instance IDs, VPC IDs, subnet IDs, command IDs and workflow run IDs below are the values recorded in this lab. A reader using another account must substitute their own values and update account-specific trust policies. A recreated subnet or instance receives a new ID; I check the lookup output before using an old command. I never copy a historical lock ID into an unrelated unlock operation.

**Prerequisites already present at the start:** AWS CLI, Git and WSL access. I installed Packer and the Session Manager plugin during this conversation. Terraform was available by the time I initialized the first root. I have not invented a Terraform installation session or claimed it happened here.

## How my security studies shaped this lab

I used this project to put ideas from three areas of study into practice. The Google Cybersecurity Certificate coursework gave me a grounding in security fundamentals, risk, investigation and the importance of recording evidence. My ISC2 Certified in Cybersecurity (CC) studies helped me think about least privilege, separation of duties and verifying access rather than trusting a request simply because it came from inside a network. I used those ideas to separate identities, restrict service paths and check who was making each AWS request.

The AWS Certified Security – Specialty **SCS-C03 learning material** helped me apply those principles to AWS: protect the root identity, use temporary access and scoped roles, control management paths, and make activity observable. In this lab I chose SSM for management instead of exposing inbound SSH. That choice follows the aim of reducing management exposure; it is not a claim that the exam universally prohibits SSH. AWS describes SSM's IAM-controlled access and closed inbound management ports in its [Session Manager guidance](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager.html).

| Learning background | How I applied it here |
| --- | --- |
| Google Cybersecurity Certificate coursework | Treat findings as evidence, investigate failures and document the risk and coverage limits rather than rely on a green badge. |
| ISC2 CC studies | Apply least privilege and separation of duties; verify identity and authorization at trust boundaries. A private IP alone does not establish trust. |
| AWS SCS-C03 learning material | Use a non-root administrative identity for lab operations, temporary CLI sessions and workload roles, restricted management access, and centralized logging. |

I am describing how these studies influenced my decisions, not claiming this lab implements a complete zero-trust architecture or that studying the SCS-C03 material means I passed that certification. The [official SCS-C03 guide](https://docs.aws.amazon.com/aws-certification/latest/security-specialty-03/security-specialty-03.html) covers infrastructure security, identity and access management, detection and other security domains that helped frame this work.

## The security principles I built into the lab

The main principle I wanted to demonstrate was **immutable infrastructure**. I prepared operating-system settings, application runtimes, scanner tools, service definitions and hardening in Packer before deployment. Terraform deployed those images. Once a host was deployed, I treated its installed software and configuration as fixed: when I needed a change, I corrected the image source, rebuilt the AMI and replaced the instance. I still read logs and checked health to understand failures.

Packer makes that approach practical by producing a reusable machine image from version-controlled build instructions. It does not technically prevent someone from changing a running server; avoiding those changes was a deliberate rule of this lab. My rule was **build the configuration before deployment; rebuild and replace afterward**. The baked startup code could retrieve environment-specific settings and short-lived credentials, but I did not use that as a way to install missing tools or repair configuration on a deployed host.

| Principle | How I applied it |
| --- | --- |
| Immutable infrastructure | Bake software and configuration into AMIs; rebuild and replace affected hosts instead of patching them in place. |
| Infrastructure as code | Define AWS resources in separate Terraform roots and review their saved plans before applying changes. |
| Least privilege | Separate Packer, planning, apply and runtime roles; scope permissions to the operations and resources each needs. The walkthrough also records where the lab policies still need improvement. |
| Separation of duties | Keep planning separate from approved applies, and use separate SonarQube analysis, reporting and administration credentials. My solo-lab self-approval is a demonstration of a gate, not independent peer review. |
| Defense in depth | Combine host firewall settings, security groups, private service paths, IAM roles and several kinds of scanning. Each control covers a different part of the system. |
| Short-lived access and secret protection | Use AWS login sessions, GitHub OIDC, instance roles and a short-lived runner registration token; keep application tokens in protected secrets rather than the repository or AMIs. |
| Controlled management access | Use SSM for access and diagnostics, with no inbound SSH rule. Packer's temporary SSH communicator travels through an SSM tunnel during image creation. |
| Early and complementary security checks | Run secrets, source and dependency checks before the reviewed application deployment, then test the running target with DAST. The scanner platform must exist first. |
| Traceability and visibility | Preserve reports and workflow results, send aggregate events to CloudWatch and notify through SNS. Distinguish tool/reporting failure from a completed scan with no findings. |
| Reproducible software inputs | Pin the application and tool versions and verify downloaded artifacts using the checksums or signatures implemented in the image build and scan workflows. |

Because Juice Shop is intentionally vulnerable, I configured findings as report-only. This lets me demonstrate detection and reporting while continuing the lab deployment. I did not hide scanner execution failures behind that policy, and I would not present the same permissive findings policy as an automatic choice for a production application.

## Why I used each tool

| Tool or service | Why I used it and what it contributes |
| --- | --- |
| Packer | Build the three AMIs with their required software and configuration already present. It supports repeatable builds and replacement-based maintenance. |
| Terraform | Describe and deploy AWS resources, expose dependencies through outputs, and keep separate state for each root. Plans make intended infrastructure changes reviewable. |
| GitHub Actions | Run the checked-in deployment and scanner steps consistently. Reusable workflows let the combined pipeline call the same jobs I tested separately. |
| Git and GitHub pull requests | Track changes to build scripts, infrastructure and workflows, and make a proposed change reviewable before merge. |
| IAM and OIDC | Give workflows and instances identities with scoped permissions, using temporary AWS credentials instead of static AWS keys in GitHub. |
| Systems Manager | Reach instances and inspect health without opening inbound SSH. It also carries the temporary Packer connection and the one-time registration parameter. |
| S3 backend and native locking | Keep Terraform state outside a disposable runner and protect each state from simultaneous writes. Workflow concurrency complements the state locks. |
| Gitleaks | Detect potential secrets in Git history, where deleting a credential from the latest file alone would not remove the exposure. |
| SonarQube and SonarScanner | Analyze the matching source release and provide a central project view and API for exporting source-code findings. |
| OWASP Dependency-Check | Identify known vulnerabilities associated with dependencies in the packaged release, with the coverage limitations recorded. |
| OWASP ZAP | Exercise the running web application within the approved target scope and produce dynamic test evidence after deployment. |
| CloudWatch Logs | Keep aggregate scan summaries and configured host/application logs available for investigation. |
| SNS | Deliver a concise scan summary to a confirmed email subscriber without sending an email for every individual issue. |
| RDS PostgreSQL and Secrets Manager | Keep SonarQube's persistent database separate from its replaceable EC2 host and let the startup process retrieve the database credentials through its runtime role. |

## Contents

1. WSL, AWS identity and repository access
2. Packer prerequisites, roles and all three images
3. Separate Terraform roots and the original manual test
4. S3 state, OIDC, protected applies and automated deployment
5. Read-only service checks and immutable replacement
6. Separate Gitleaks, SonarQube, Dependency-Check and ZAP workflows
7. CloudWatch, SNS and evidence
8. Combined pipeline, trust boundaries, cleanup and challenges


## 1. Recover my IAM sign-in, then start a short-lived AWS login session

I started in WSL as the Linux user `devsecops`. Before building anything, I recovered access to my IAM user and checked which AWS identity the CLI was using. A local Linux prompt saying `root` is different from the AWS root identity; the ARN returned by STS is what I checked.

```bash
cd ~/projects
mkdir project-3-secure-cicd-pipeline
cd project-3-secure-cicd-pipeline
```

### Recover the IAM user's console password

In my recorded recovery, I first used the existing `root-recovery` profile. Running this command opened a browser sign-in link. I followed that link and signed in as the AWS account root user for the recovery session.

```bash
aws login --profile root-recovery

aws sts get-caller-identity \
  --profile root-recovery \
  --query Arn \
  --output text
```

I checked that the returned ARN ended in `:root` before using the recovery profile. A profile name is only a local label; a profile called `root-recovery` can still point to a different identity. This was the recovery route I used when I could not access my IAM account, not a requirement to sign in as root whenever an IAM user's CLI session expires.

I then used this Python-assisted command to set a new console password for `mds-devsecops-lab`. It prompts without echoing the password, checks the confirmation, writes the request into a restricted temporary file, and removes that file on exit. I did not paste a real password into the command or commit one to the repository.

```bash
(
  set -e
  umask 077

  login_input="$(mktemp)"
  trap 'rm -f "$login_input"' EXIT

  python3 - "$login_input" <<'PY'
import getpass
import json
import sys

password = getpass.getpass("New password for mds-devsecops-lab: ")
confirmation = getpass.getpass("Enter it again: ")

if not password or password != confirmation:
    raise SystemExit("Passwords are empty or do not match. Nothing changed.")

with open(sys.argv[1], "w") as file:
    json.dump({
        "UserName": "mds-devsecops-lab",
        "Password": password,
        "PasswordResetRequired": False
    }, file)
PY

  aws iam update-login-profile \
    --cli-input-json "file://$login_input" \
    --profile root-recovery \
    --no-cli-auto-prompt

  printf 'IAM user password updated successfully.\n'
)
```

The important distinction is that this script resets the **IAM console password**. It does not generate short-lived API credentials, renew an expired CLI session or reset the root password. AWS documents that behaviour in [update-login-profile](https://docs.aws.amazon.com/cli/latest/reference/iam/update-login-profile.html). An administrator authorized to reset IAM login profiles can perform this operation too; it is not inherently a root-only task.

### Leave the recovery identity and log in as my IAM user

Once access was recovered, I ended the cached root-recovery CLI session, then signed in through the browser as `mds-devsecops-lab` using the new password. I selected the IAM user session rather than reusing a root browser session.

```bash
aws logout --profile root-recovery

aws login --profile mds-devsecops-lab

aws sts get-caller-identity \
  --profile mds-devsecops-lab \
  --query Arn \
  --output text
```

I expected the ARN to end in `:user/mds-devsecops-lab`. The `aws login` browser flow obtains temporary CLI credentials; the CLI manages their refresh within the allowed login session. When that session expires, I run `aws login --profile mds-devsecops-lab` again. I do not reset the console password simply because the temporary credentials expired. This is the distinction described in [AWS's local-development login guidance](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-sign-in.html).

```bash
export AWS_PROFILE=mds-devsecops-lab
export AWS_REGION=us-east-1
export AWS_DEFAULT_REGION=us-east-1

aws sts get-caller-identity
packer version
```

The existing directory was later replaced by a clone, so I did not repeat `mkdir` on every visit. I continued the lab with the IAM user for authorized administrative setup and with the dedicated assumed roles for Packer and the pipeline.

### Why I kept root out of routine lab work

A principle reinforced by my AWS security studies was to keep the root identity protected and avoid it for ordinary administration. Root has account-wide powers, including operations reserved to root; accidental use or compromise therefore has a particularly large impact. I documented my root recovery as an exception and moved back to a non-root identity afterward. AWS recommends protecting root, using it only where required, enabling MFA and avoiding root access keys in its [root-user guidance](https://docs.aws.amazon.com/IAM/latest/UserGuide/root-user-best-practices.html).

For this lab I used my IAM user for the administrative work I was authorized to perform instead of deploying as root. Administrative permissions are still powerful: `AdministratorAccess` is not least privilege, and replacing root with an unrestricted user does not remove that risk. I used separate scoped roles for automation. AWS's broader recommendation is federated human access with temporary credentials where possible, workload roles, MFA and least privilege—not permanently granting every operator administrator permissions. See [IAM security best practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html).


## 2. Install Packer and the Session Manager plugin

I needed Packer to prepare software, services and hardening before deployment. The Session Manager plugin supports its temporary SSM tunnel without an inbound SSH rule.

I installed Packer from HashiCorp's package repository and the local Session Manager plugin. The version checks returned Packer 1.16.2 and plugin 1.2.896.0 in the recorded session. A completed installer returning to the prompt is different from a command that is still waiting.


```bash
sudo apt-get update
sudo apt-get install -y wget gpg lsb-release

wget -O- https://apt.releases.hashicorp.com/gpg \
  | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(grep -oP '(?<=UBUNTU_CODENAME=).*' /etc/os-release || lsb_release -cs) main" \
  | sudo tee /etc/apt/sources.list.d/hashicorp.list

sudo apt-get update
sudo apt-get install -y packer
```


```bash
packer version
aws sts get-caller-identity
```


```bash
curl "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb" \
  -o session-manager-plugin.deb

sudo dpkg -i session-manager-plugin.deb
session-manager-plugin --version
```

## 3. Authenticate GitHub and clone the repository

Git and GitHub gave the build scripts and workflows a versioned source and review history. A later replacement could then be traced to a specific change.

I used HTTPS with GitHub CLI for the repository. When browser authentication timed out, I checked connectivity before retrying authentication. I selected repository access for the private repository at that stage; visibility was changed later. I did not put a token in a Git command or commit it.


```bash
gh auth login
```


```bash
curl -I --connect-timeout 10 https://api.github.com/
curl -I --connect-timeout 10 https://github.com/
```


```bash
gh auth status
```


```bash
mkdir -p ~/Downloads
mv ~/projects/project-3-secure-cicd-pipeline/session-manager-plugin.deb ~/Downloads/

cd ~/projects
git clone https://github.com/DelaneKay/project-3-secure-cicd-pipeline.git
```


```bash
cd ~/projects/project-3-secure-cicd-pipeline
git status --short --branch
```

The original folder contained the downloaded Session Manager package and was not a Git repository. The move-and-clone commands above belong to that initial recovery, not every future checkout. I used `git status --short --branch` to confirm that `master` tracked `origin/master`.

## 4. Create the temporary builder role and instance profile

I gave the temporary EC2 builder its own role so it could use SSM without inheriting the operator's AWS build permissions.

I created the EC2 role used by temporary Packer builders to register with Systems Manager. This role is separate from my Packer operator role and from the runtime roles used by the application, SonarQube and scanner. I ran the creation once; if a later command failed, I inspected the resources rather than blindly recreating them.


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


```bash
aws iam list-attached-role-policies \
  --role-name project-3-packer-builder-role \
  --profile mds-devsecops-lab \
  --output table
```

## 5. Give Packer its own assumed role

I used an assumed operator role so Packer could perform image-build and cleanup API calls using temporary credentials. The human login remained outside the image.

The first build could not find usable credentials even though AWS CLI could identify my user. I created an operator role, granted my IAM user permission to assume it, and configured a login-backed credential process. Packer then used the `project-3-packer` role profile. The policy below is the actual lab bootstrap policy; its regional wildcard permissions are a lab limitation, not a claim of production-grade least privilege.


```bash
set -euo pipefail
umask 077

profile="mds-devsecops-lab"
user_name="mds-devsecops-lab"
operator_role="project-3-packer-operator-role"
trust_file="$(mktemp)"
assume_policy_file="$(mktemp)"
trap 'rm -f "$trust_file" "$assume_policy_file"' EXIT

account_id="$(aws sts get-caller-identity \
  --profile "$profile" \
  --region us-east-1 \
  --query Account --output text)"
caller_arn="$(aws sts get-caller-identity \
  --profile "$profile" \
  --region us-east-1 \
  --query Arn --output text)"

if [[ "$caller_arn" != "arn:aws:iam::${account_id}:user/${user_name}" ]]; then
  echo "Unexpected AWS identity: $caller_arn"
  exit 1
fi

cat > "$trust_file" <<JSON
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::${account_id}:user/${user_name}"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
JSON

cat > "$assume_policy_file" <<JSON
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "sts:AssumeRole",
      "Resource": "arn:aws:iam::${account_id}:role/${operator_role}"
    }
  ]
}
JSON

aws iam create-role \
  --role-name "$operator_role" \
  --assume-role-policy-document "file://$trust_file" \
  --description "Packer operator role for Project 3 AMI builds" \
  --max-session-duration 3600 \
  --profile "$profile"

aws iam put-user-policy \
  --user-name "$user_name" \
  --policy-name project-3-assume-packer-operator \
  --policy-document "file://$assume_policy_file" \
  --profile "$profile"

aws iam get-role \
  --role-name "$operator_role" \
  --profile "$profile" \
  --query 'Role.Arn' \
  --output text
```


```bash
set -euo pipefail
umask 077

policy_file="$(mktemp)"
trap 'rm -f "$policy_file"' EXIT

cat > "$policy_file" <<'JSON'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "PackerEc2ImageBuildInUsEast1",
      "Effect": "Allow",
      "Action": [
        "ec2:AttachVolume",
        "ec2:CopyImage",
        "ec2:CreateImage",
        "ec2:CreateKeyPair",
        "ec2:CreateSnapshot",
        "ec2:CreateTags",
        "ec2:CreateVolume",
        "ec2:DeleteKeyPair",
        "ec2:DeleteSnapshot",
        "ec2:DeleteVolume",
        "ec2:DeregisterImage",
        "ec2:DescribeImageAttribute",
        "ec2:DescribeImages",
        "ec2:DescribeInstances",
        "ec2:DescribeInstanceStatus",
        "ec2:DescribeRegions",
        "ec2:DescribeSecurityGroups",
        "ec2:DescribeSubnets",
        "ec2:DescribeSnapshots",
        "ec2:DescribeTags",
        "ec2:DescribeVolumes",
        "ec2:DetachVolume",
        "ec2:ModifyImageAttribute",
        "ec2:ModifyInstanceAttribute",
        "ec2:RegisterImage",
        "ec2:RunInstances",
        "ec2:StopInstances",
        "ec2:TerminateInstances"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "aws:RequestedRegion": "us-east-1"
        }
      }
    },
    {
      "Sid": "PackerSsmTunnelInUsEast1",
      "Effect": "Allow",
      "Action": [
        "ssm:StartSession",
        "ssm:TerminateSession",
        "ssm:ResumeSession"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "aws:RequestedRegion": "us-east-1"
        }
      }
    },
    {
      "Sid": "InspectOnlyPackerBuilderRole",
      "Effect": "Allow",
      "Action": [
        "iam:GetInstanceProfile",
        "iam:GetRole"
      ],
      "Resource": [
        "arn:aws:iam::YOUR_ACCOUNT_ID:instance-profile/project-3-packer-builder-profile",
        "arn:aws:iam::YOUR_ACCOUNT_ID:role/project-3-packer-builder-role"
      ]
    },
    {
      "Sid": "PassOnlyPackerBuilderRoleToEc2",
      "Effect": "Allow",
      "Action": "iam:PassRole",
      "Resource": "arn:aws:iam::YOUR_ACCOUNT_ID:role/project-3-packer-builder-role",
      "Condition": {
        "StringEquals": {
          "iam:PassedToService": "ec2.amazonaws.com"
        }
      }
    }
  ]
}
JSON

python3 -m json.tool "$policy_file" >/dev/null

aws iam put-role-policy \
  --role-name project-3-packer-operator-role \
  --policy-name project-3-packer-operator-policy \
  --policy-document "file://$policy_file" \
  --profile mds-devsecops-lab

aws iam get-role-policy \
  --role-name project-3-packer-operator-role \
  --policy-name project-3-packer-operator-policy \
  --profile mds-devsecops-lab \
  --query '[RoleName,PolicyName]' \
  --output text
```


```bash
set -euo pipefail

aws configure set credential_process \
  'aws configure export-credentials --profile mds-devsecops-lab --format process' \
  --profile mds-devsecops-lab-packer-source

aws configure set region us-east-1 \
  --profile mds-devsecops-lab-packer-source

aws configure set role_arn \
  arn:aws:iam::YOUR_ACCOUNT_ID:role/project-3-packer-operator-role \
  --profile project-3-packer

aws configure set source_profile mds-devsecops-lab-packer-source \
  --profile project-3-packer

aws configure set role_session_name project-3-packer-build \
  --profile project-3-packer

aws configure set region us-east-1 \
  --profile project-3-packer

aws sts get-caller-identity \
  --profile project-3-packer \
  --region us-east-1 \
  --query Arn \
  --output text
```

I expected `assumed-role/project-3-packer-operator-role/project-3-packer-build` from the final identity check. The operator policy does not grant every discovery call: later `DescribeVpcs` and public SSM AMI-parameter lookups were performed with the IAM user's profile. I kept the actual image build on the role.

## 6. Select Ubuntu 24.04 and inspect the bootstrap network

I selected the base image and checked its owner before building on it. A consistent verified base reduces variation between the three host images.

I chose Ubuntu 24.04 LTS amd64 and retrieved Canonical's public AMI parameter. The recorded image was `ami-REPLACE_WITH_YOUR_ID`, owned by Canonical account `099720109477`. Before building, I inspected the default VPC, subnet public-IP behavior and route to the internet gateway.


```bash
aws ssm get-parameter \
  --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
  --query 'Parameter.Value' \
  --output text \
  --profile mds-devsecops-lab \
  --region us-east-1
```


```bash
aws ec2 describe-images \
  --image-ids ami-REPLACE_WITH_YOUR_ID \
  --query 'Images[0].[Name,Architecture,OwnerId,State]' \
  --output table \
  --profile mds-devsecops-lab \
  --region us-east-1
```


```bash
DEFAULT_VPC_ID=$(aws ec2 describe-vpcs \
  --region us-east-1 \
  --profile mds-devsecops-lab \
  --filters Name=isDefault,Values=true \
  --query 'Vpcs[0].VpcId' \
  --output text)

printf 'Default VPC: %s\n' "$DEFAULT_VPC_ID"

if [ "$DEFAULT_VPC_ID" != "None" ]; then
  aws ec2 describe-subnets \
    --region us-east-1 \
    --profile mds-devsecops-lab \
    --filters "Name=vpc-id,Values=$DEFAULT_VPC_ID" \
    --query 'Subnets[].{Subnet:SubnetId,AZ:AvailabilityZone,AutoPublicIP:MapPublicIpOnLaunch}' \
    --output table
fi
```


```bash
aws ec2 describe-route-tables \
  --region us-east-1 \
  --profile mds-devsecops-lab \
  --filters Name=vpc-id,Values=vpc-REPLACE_WITH_YOUR_ID \
  --query 'RouteTables[].{RouteTable:RouteTableId,Main:Associations[?Main==`true`]|[0].Main,Subnets:Associations[].SubnetId,Routes:Routes[].{Destination:DestinationCidrBlock,Gateway:GatewayId,State:State}}' \
  --output json
```

## 7. Create a no-ingress Packer security group

The temporary builder needed outbound download and management access, not inbound administration. Its dedicated security group made that boundary explicit.

I stopped using the default security group for builds and created a dedicated group with no inbound rules. Its outbound rules allowed TCP 80 for package mirrors and TCP 443 for SSM and downloads. Packer used its SSH communicator inside an SSM tunnel; this lab did not open public port 22. The temporary communicator is still SSH internally, so I do not describe it as an SSH-free Packer protocol.


```bash
set -euo pipefail

PACKER_SG_ID="$(aws ec2 create-security-group \
  --group-name project-3-packer-builder \
  --description "Temporary no-ingress security group for SSM-connected Packer builds" \
  --vpc-id vpc-REPLACE_WITH_YOUR_ID \
  --tag-specifications 'ResourceType=security-group,Tags=[{Key=Project,Value=project-3-secure-cicd-pipeline},{Key=Purpose,Value=packer-builder}]' \
  --query GroupId \
  --output text \
  --profile mds-devsecops-lab \
  --region us-east-1)"

printf 'Created Packer builder security group: %s\n' "$PACKER_SG_ID"

aws ec2 revoke-security-group-egress \
  --group-id "$PACKER_SG_ID" \
  --ip-permissions '[{"IpProtocol":"-1","IpRanges":[{"CidrIp":"0.0.0.0/0"}]}]' \
  --profile mds-devsecops-lab \
  --region us-east-1

aws ec2 authorize-security-group-egress \
  --group-id "$PACKER_SG_ID" \
  --ip-permissions '[{"IpProtocol":"tcp","FromPort":80,"ToPort":80,"IpRanges":[{"CidrIp":"0.0.0.0/0","Description":"HTTP package mirrors during Packer build"}]},{"IpProtocol":"tcp","FromPort":443,"ToPort":443,"IpRanges":[{"CidrIp":"0.0.0.0/0","Description":"HTTPS for SSM and build downloads"}]}]' \
  --profile mds-devsecops-lab \
  --region us-east-1

aws ec2 describe-security-groups \
  --group-ids "$PACKER_SG_ID" \
  --query 'SecurityGroups[0].{GroupId:GroupId,Ingress:IpPermissions,Egress:IpPermissionsEgress}' \
  --output json \
  --profile mds-devsecops-lab \
  --region us-east-1
```

## 8. Create the Juice Shop image files and build my first AMI

Here I moved Juice Shop installation and host configuration into Packer. I prepared the runtime, service and firewall before launch; a later correction meant rebuilding and replacing the host.

I created the Juice Shop template and installation script, then formatted, initialized and validated the template before building. I used the corrected checked-in installation script, including its UFW settings. An early SSM Agent command used `snap enable`; I corrected it to `snap start` before the successful build.


```bash
cd ~/projects/project-3-secure-cicd-pipeline
mkdir -p packer/juice-shop/scripts
```


```bash
packer init packer/juice-shop
```


```bash
cd ~/projects/project-3-secure-cicd-pipeline

if ! grep -q 'ssh_clear_authorized_keys' packer/juice-shop/juice-shop.pkr.hcl; then
  sed -i '/ssh_timeout[[:space:]]*=/a\  ssh_clear_authorized_keys = true' \
    packer/juice-shop/juice-shop.pkr.hcl
fi

packer fmt packer/juice-shop

packer validate \
  -var 'source_ami_id=ami-REPLACE_WITH_YOUR_ID' \
  -var 'subnet_id=subnet-REPLACE_WITH_YOUR_ID' \
  -var 'security_group_id=sg-REPLACE_WITH_YOUR_ID' \
  packer/juice-shop
```


```bash
sed -i 's/^[[:space:]]*snap enable amazon-ssm-agent$/  snap start amazon-ssm-agent/' \
  packer/juice-shop/scripts/install-juice-shop.sh

sed -n '100,112p' packer/juice-shop/scripts/install-juice-shop.sh
```


```bash
cd ~/projects/project-3-secure-cicd-pipeline

AWS_PROFILE=project-3-packer AWS_REGION=us-east-1 packer build \
  -var 'source_ami_id=ami-REPLACE_WITH_YOUR_ID' \
  -var 'subnet_id=subnet-REPLACE_WITH_YOUR_ID' \
  -var 'security_group_id=sg-REPLACE_WITH_YOUR_ID' \
  packer/juice-shop
```

I baked Node.js, Juice Shop 20.3.0, its systemd service, SSM support, CloudWatch configuration and host firewall into the image. The [Packer template](../packer/juice-shop/juice-shop.pkr.hcl) and [installation script](../packer/juice-shop/scripts/install-juice-shop.sh) define what the build installs. I did not run that provisioning script against the deployed application server.

## 9. Create the SonarQube image and validate all required inputs

SonarQube needed a separate image because it serves a different purpose and uses a different runtime from Juice Shop. I baked its software and startup mechanism before deployment.

I created a separate SonarQube template, installer and CloudWatch installer. I loaded `version.env` because a valid template still needs values for source AMI, subnet, security group, SonarQube version and Java package. Running validation without those values produced the unset-variable errors we saw.


```bash
cd ~/projects/project-3-secure-cicd-pipeline

cat > packer/sonarqube/version.env <<'EOF'
SONARQUBE_VERSION=26.10.0.133078
JAVA_PACKAGE=openjdk-21-jdk
EOF
```


```bash
nano packer/sonarqube/scripts/install-sonarqube.sh
```


```bash
cd ~/projects/project-3-secure-cicd-pipeline

cat > packer/sonarqube/sonarqube.pkr.hcl <<'EOF'
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
}
EOF
```


```bash
cd ~/projects/project-3-secure-cicd-pipeline
packer fmt packer/sonarqube
packer init packer/sonarqube

set -a
source packer/sonarqube/version.env
set +a

packer validate \
  -var 'source_ami_id=ami-REPLACE_WITH_YOUR_ID' \
  -var 'subnet_id=subnet-REPLACE_WITH_YOUR_ID' \
  -var 'security_group_id=sg-REPLACE_WITH_YOUR_ID' \
  -var "sonarqube_version=${SONARQUBE_VERSION}" \
  -var "java_package=${JAVA_PACKAGE}" \
  packer/sonarqube
```


```bash
cd ~/projects/project-3-secure-cicd-pipeline

cat > packer/sonarqube/scripts/install-cloudwatch-agent.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

WORK_DIR="$(mktemp -d)"
GNUPGHOME="$WORK_DIR/gnupg"
AGENT_URL="https://amazoncloudwatch-agent.s3.amazonaws.com/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

mkdir -m 700 -p "$GNUPGHOME"

curl --fail --silent --show-error --location --retry 3 \
  --output "$WORK_DIR/amazon-cloudwatch-agent.gpg" \
  https://amazoncloudwatch-agent.s3.amazonaws.com/assets/amazon-cloudwatch-agent.gpg

gpg --batch --homedir "$GNUPGHOME" \
  --import "$WORK_DIR/amazon-cloudwatch-agent.gpg" >/dev/null

fingerprint="$(gpg --batch --homedir "$GNUPGHOME" --with-colons --fingerprint \
  | awk -F: '$1 == "fpr" {print $10; exit}')"

if [[ "$fingerprint" != "937616F3450B7D806CBD9725D58167303B789C72" ]]; then
  echo "CloudWatch Agent signing-key fingerprint did not match." >&2
  exit 1
fi

curl --fail --silent --show-error --location --retry 3 \
  --output "$WORK_DIR/amazon-cloudwatch-agent.deb" \
  "$AGENT_URL"

curl --fail --silent --show-error --location --retry 3 \
  --output "$WORK_DIR/amazon-cloudwatch-agent.deb.sig" \
  "${AGENT_URL}.sig"

gpg --batch --homedir "$GNUPGHOME" \
  --verify "$WORK_DIR/amazon-cloudwatch-agent.deb.sig" \
  "$WORK_DIR/amazon-cloudwatch-agent.deb"

dpkg -i "$WORK_DIR/amazon-cloudwatch-agent.deb"

install -d -m 0755 /opt/aws/amazon-cloudwatch-agent/etc

cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<'JSON'
{
  "agent": {
    "metrics_collection_interval": 60
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/opt/sonarqube/logs/sonar.log",
            "log_group_name": "/project-3/sonarqube",
            "log_stream_name": "{instance_id}/sonar.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/opt/sonarqube/logs/web.log",
            "log_group_name": "/project-3/sonarqube",
            "log_stream_name": "{instance_id}/web.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/opt/sonarqube/logs/ce.log",
            "log_group_name": "/project-3/sonarqube",
            "log_stream_name": "{instance_id}/ce.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/opt/sonarqube/logs/es.log",
            "log_group_name": "/project-3/sonarqube",
            "log_stream_name": "{instance_id}/es.log",
            "timezone": "UTC"
          }
        ]
      }
    }
  },
  "metrics": {
    "namespace": "Project3/SonarQube",
    "metrics_collected": {
      "mem": {
        "measurement": ["mem_used_percent"]
      },
      "disk": {
        "measurement": ["used_percent"],
        "resources": ["/"]
      }
    }
  }
}
JSON

chmod 0644 /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
EOF
```


```bash
cd ~/projects/project-3-secure-cicd-pipeline

python3 - <<'PY'
from pathlib import Path

path = Path("packer/sonarqube/sonarqube.pkr.hcl")
text = path.read_text()

if "install-cloudwatch-agent.sh" in text:
    raise SystemExit("CloudWatch provisioner is already present.")

insert_at = text.rfind("\n}")
if insert_at < 0:
    raise SystemExit("Could not find the end of the Packer build block.")

block = """
  provisioner "shell" {
    script          = "${path.root}/scripts/install-cloudwatch-agent.sh"
    execute_command = "sudo -E bash '{{ .Path }}'"
  }
"""

path.write_text(text[:insert_at] + block + text[insert_at:])
PY

packer fmt packer/sonarqube
grep -n -A5 'install-cloudwatch-agent.sh' packer/sonarqube/sonarqube.pkr.hcl
```


```bash
cd ~/projects/project-3-secure-cicd-pipeline

set -a
source packer/sonarqube/version.env
set +a

AWS_PROFILE=project-3-packer AWS_REGION=us-east-1 packer build \
  -var 'source_ami_id=ami-REPLACE_WITH_YOUR_ID' \
  -var 'subnet_id=subnet-REPLACE_WITH_YOUR_ID' \
  -var 'security_group_id=sg-REPLACE_WITH_YOUR_ID' \
  -var "sonarqube_version=${SONARQUBE_VERSION}" \
  -var "java_package=${JAVA_PACKAGE}" \
  packer/sonarqube
```

Those are the initial build steps. The first service definition was later replaced with the baked startup helper. I followed the immutable rebuild loop in step 20 for the corrected image instead of copying the original service definition back over the final files.

## 10. Create the scanner runner image with pinned tools

A separate runner image kept scanner software off the target application and SonarQube hosts. Baking the tools made a replacement repeatable instead of depending on live package installation.

I built a third AMI for the AWS scanner runner. I pinned the runner, Gitleaks, SonarScanner, Dependency-Check, ZAP, Terraform, AWS CLI and Java versions. Subsequent image-build fixes added Node.js/npm and tested tool execution as `actions-runner`. I did not install Gitleaks in WSL to satisfy a workflow intended to run in AWS.


```bash
cd ~/projects/project-3-secure-cicd-pipeline
mkdir -p packer/github-runner/scripts
```


```bash
cd ~/projects/project-3-secure-cicd-pipeline

cat > packer/github-runner/versions.env <<'EOF'
GITHUB_RUNNER_VERSION=2.338.2
GITLEAKS_VERSION=8.30.0
SONAR_SCANNER_VERSION=8.1.0.6389
DEPENDENCY_CHECK_VERSION=13.0.0
ZAP_VERSION=2.17.0
TERRAFORM_VERSION=1.16.2
AWS_CLI_VERSION=2.39.1
JAVA_PACKAGE=openjdk-21-jdk
EOF
```


```bash
nano packer/github-runner/scripts/install-runner.sh
```


```hcl
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
  default = "ami-REPLACE_WITH_YOUR_ID"
}

variable "subnet_id" {
  type    = string
  default = "subnet-REPLACE_WITH_YOUR_ID"
}

variable "security_group_id" {
  type    = string
  default = "sg-REPLACE_WITH_YOUR_ID"
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
```


```bash
packer init packer/github-runner
```


```bash
set -a
source packer/github-runner/versions.env
set +a

packer validate \
  -var "github_runner_version=$GITHUB_RUNNER_VERSION" \
  -var "gitleaks_version=$GITLEAKS_VERSION" \
  -var "sonar_scanner_version=$SONAR_SCANNER_VERSION" \
  -var "dependency_check_version=$DEPENDENCY_CHECK_VERSION" \
  -var "zap_version=$ZAP_VERSION" \
  -var "terraform_version=$TERRAFORM_VERSION" \
  -var "aws_cli_version=$AWS_CLI_VERSION" \
  -var "java_package=$JAVA_PACKAGE" \
  packer/github-runner
```


```bash
set -a
source packer/github-runner/versions.env
set +a

AWS_PROFILE=project-3-packer packer build \
  -var "github_runner_version=$GITHUB_RUNNER_VERSION" \
  -var "gitleaks_version=$GITLEAKS_VERSION" \
  -var "sonar_scanner_version=$SONAR_SCANNER_VERSION" \
  -var "dependency_check_version=$DEPENDENCY_CHECK_VERSION" \
  -var "zap_version=$ZAP_VERSION" \
  -var "terraform_version=$TERRAFORM_VERSION" \
  -var "aws_cli_version=$AWS_CLI_VERSION" \
  -var "java_package=$JAVA_PACKAGE" \
  packer/github-runner
```

The [runner installer](../packer/github-runner/scripts/install-runner.sh) and [Packer template](../packer/github-runner/github-runner.pkr.hcl) define the runner build. A runner AMI contains software, not a permanent GitHub registration token.

## 11. Commit the image build files

I checked the Packer files before staging them. My first commit failed because Git had no author name; I set the repository's author from my authenticated GitHub account, committed again and pushed. A later 403 on push required fixing GitHub write permission, rather than changing AWS access.


```bash
git status --short
```


```bash
find packer -maxdepth 4 -type f -print | sort
```


```bash
git add packer
git diff --cached --stat
git status --short
```


```bash
gh_user="$(gh api user --jq .login)"
gh_user_id="$(gh api user --jq .id)"
git config user.name "$gh_user"
git config user.email "${gh_user_id}+${gh_user}@users.noreply.github.com"

git commit -m "Add hardened Packer AMI builds for Lab 3"
```


```bash
git commit -m "Add hardened Packer AMI builds for Lab 3"
```


```bash
gh auth status --hostname github.com
```


```bash
git push origin master
```


```bash
git status --short --branch
```

## 12. Split Terraform into independent roots

I introduced Terraform to describe the AWS infrastructure surrounding the images. Separate roots made ownership, state and dependency order explicit.

I created five separate root directories rather than one long Terraform file. Network owns the VPC, subnets, routes and security groups; database owns RDS; observability owns log groups and SNS; compute owns Juice Shop and the runner; sonarqube owns the SonarQube instance. At this point only network and database contained files—empty directories were not missing Git commits.


```bash
mkdir -p terraform/network terraform/database terraform/compute terraform/sonarqube terraform/observability
```


```bash
nano terraform/.gitignore
```


```gitignore
**/.terraform/
*.tfstate
*.tfstate.*
*.tfstate.lock.info
*.tfvars
*.tfvars.json
*.tfplan
crash.log
crash.*.log
```


```bash
cd ~/projects/project-3-secure-cicd-pipeline

find terraform -maxdepth 3 -type f \
  ! -path '*/.terraform/*' \
  ! -name 'terraform.tfstate*' \
  ! -name '*.tfplan' \
  -print | sort
```


```bash
cd ~/projects/project-3-secure-cicd-pipeline
find terraform/compute terraform/sonarqube terraform/observability \
  -maxdepth 2 -type f -print 2>/dev/null | sort
```

I kept the definitions in the [network](../terraform/network), [database](../terraform/database), [compute](../terraform/compute), [observability](../terraform/observability) and [SonarQube](../terraform/sonarqube) roots. Separate roots mean separate state and explicit execution order, not that Terraform automatically runs every directory.

## 13. Validate and test the original network layer manually

These manual Terraform runs were initial infrastructure tests before I automated execution. They were a development stage, not the final routine deployment process.

During the initial build I ran Terraform locally to test the network root. I used two public and two private subnets in `10.20.0.0/16` and selected interface VPC endpoints. The plan initially showed 14 resources, then 21 after the remaining security groups were added. This manual stage is part of the history; it is not the final routine deployment method.


```bash
terraform -chdir=terraform/network init
```


```bash
terraform -chdir=terraform/network validate
```


```bash
cd ~/projects/project-3-secure-cicd-pipeline
terraform -chdir=terraform/network fmt
terraform -chdir=terraform/network validate
```


```hcl
aws_region = "us-east-1"

project_name = "project-3-secure-cicd-pipeline"

vpc_cidr = "10.20.0.0/16"

availability_zones = [
  "us-east-1a",
  "us-east-1b",
]

public_subnet_cidrs = [
  "10.20.1.0/24",
  "10.20.2.0/24",
]

private_subnet_cidrs = [
  "10.20.11.0/24",
  "10.20.12.0/24",
]
```


```bash
cd ~/projects/project-3-secure-cicd-pipeline
terraform -chdir=terraform/network apply
```


```bash
cd ~/projects/project-3-secure-cicd-pipeline
terraform -chdir=terraform/network apply
```


```bash
cd ~/projects/project-3-secure-cicd-pipeline
terraform -chdir=terraform/network fmt
terraform -chdir=terraform/network validate
```


```bash
cd ~/projects/project-3-secure-cicd-pipeline
terraform -chdir=terraform/network apply
```

## 14. Create and test the original SonarQube database layer

RDS kept SonarQube's persistent database separate from its replaceable EC2 server. Terraform provisions that managed service; Packer builds the server image.

I checked orderable PostgreSQL 17 versions, wrote the RDS and subnet-group files, and validated the database root before its original manual apply. RDS is a managed service, so it was created by Terraform, not baked by Packer. The recorded class was `db.t4g.micro`; the database was encrypted and private.


```bash
cd ~/projects/project-3-secure-cicd-pipeline
cat packer/sonarqube/version.env
aws rds describe-orderable-db-instance-options \
  --engine postgres \
  --db-instance-class db.t4g.micro \
  --vpc \
  --region us-east-1 \
  --profile mds-devsecops-lab \
  --query "OrderableDBInstanceOptions[?starts_with(EngineVersion, '17.')].EngineVersion" \
  --output text
```


```bash
cd ~/projects/project-3-secure-cicd-pipeline
nano terraform/database/terraform.tfvars
```


```hcl
db_engine_version = "17.11"
db_instance_class = "db.t4g.micro"
```


```bash
cd ~/projects/project-3-secure-cicd-pipeline
nano terraform/database/database.tf
```


```hcl
resource "aws_db_instance" "sonarqube" {
  identifier = var.db_identifier

  engine         = "postgres"
  engine_version = var.db_engine_version
  instance_class = var.db_instance_class

  db_name  = var.db_name
  username = var.db_master_username
  port     = 5432

  manage_master_user_password = true

  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true

  db_subnet_group_name   = aws_db_subnet_group.sonarqube.name
  vpc_security_group_ids = [
    data.terraform_remote_state.network.outputs.database_security_group_id
  ]
  publicly_accessible = false

  multi_az                   = false
  backup_retention_period    = 0
  auto_minor_version_upgrade = true

  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  deletion_protection = false
  skip_final_snapshot = true
  copy_tags_to_snapshot = true

  tags = {
    Name        = var.db_identifier
    Project     = var.project_name
    Environment = "lab"
    ManagedBy   = "Terraform"
  }
}
```


```bash
cd ~/projects/project-3-secure-cicd-pipeline
nano terraform/database/outputs.tf
```


```hcl
output "db_instance_identifier" {
  description = "Identifier of the SonarQube PostgreSQL instance."
  value       = aws_db_instance.sonarqube.identifier
}

output "db_address" {
  description = "Private endpoint hostname for the SonarQube PostgreSQL instance."
  value       = aws_db_instance.sonarqube.address
}

output "db_port" {
  description = "Port used by the SonarQube PostgreSQL instance."
  value       = aws_db_instance.sonarqube.port
}

output "db_name" {
  description = "Database name created for SonarQube."
  value       = aws_db_instance.sonarqube.db_name
}

output "master_user_secret_arn" {
  description = "Secrets Manager ARN for the RDS-managed database credentials."
  value       = aws_db_instance.sonarqube.master_user_secret[0].secret_arn
}
```


```bash
cd ~/projects/project-3-secure-cicd-pipeline
terraform -chdir=terraform/database fmt
terraform -chdir=terraform/database init
terraform -chdir=terraform/database validate
```


```bash
cd ~/projects/project-3-secure-cicd-pipeline
terraform -chdir=terraform/database apply
```

My original state reference was local. I later changed both roots to S3-backed state for GitHub execution. I did not treat an existing AWS database as automatically managed just because another backend was empty; that caused the import challenge recorded below.

## 15. Move routine Terraform execution into GitHub Actions

GitHub Actions replaced repeated routine deployment commands with checked-in jobs. The reusable layer workflow runs the same plan-and-apply logic for each root.

I kept the five roots but put the repeated init/plan/apply logic in `terraform-layer.yml`. The deployment workflow calls it in dependency order. GitHub-hosted runners were explicitly allowed for Terraform; security scanners stayed on the AWS runner. I committed the roots and workflows so a runner could actually check out the same code I had tested.


```bash
git add -A
git diff --cached --check
git diff --cached --stat
git diff --cached --name-only
```


```bash
git add -A
git status --short
```


```bash
git diff --cached --check && git commit -m "Add Terraform CI and AWS Gitleaks workflow"
```


```bash
git push origin master
```

I moved Gitleaks to its [AWS scanner workflow](../.github/workflows/gitleaks-aws.yml) and retained formatting, validation and Checkov in Terraform validation. Pull requests validate without AWS deployment credentials; trusted post-merge or manual workflow deployment uses OIDC.

## 16. Bootstrap the private remote-state bucket

A disposable workflow runner cannot be the permanent home of Terraform state. S3 keeps the state between runs, and native locking protects each state against concurrent writes.

Before GitHub could initialize an S3 backend, I created the state bucket with the repository bootstrap script. This was a one-time AWS CLI bootstrap, not a Terraform root. The script enables versioning and encryption, blocks public access and rejects insecure transport. Each root uses `project-3/<root>/terraform.tfstate` with native `.tflock` locking.


```bash
cd ~/projects/project-3-secure-cicd-pipeline

aws sts get-caller-identity --profile mds-devsecops-lab
```


```bash
AWS_PROFILE=mds-devsecops-lab AWS_REGION=us-east-1 \
  ./scripts/bootstrap-terraform-state.sh
```


```bash
aws s3api head-bucket \
  --bucket project-3-tfstate-YOUR_ACCOUNT_ID-us-east-1 \
  --expected-bucket-owner YOUR_ACCOUNT_ID \
  --profile mds-devsecops-lab \
  --region us-east-1
```

## 17. Create the OIDC provider and Terraform roles

OIDC let a trusted GitHub job obtain temporary AWS credentials instead of storing an AWS access key. The plan and apply roles have separate trust and permission scopes.

I created the GitHub OIDC provider and separate plan/apply roles, validated their permission documents with Access Analyzer, and attached the policies. Access Analyzer returned `[]` in that check; that meant it found no reported policy issues, not that every future AWS operation had been proven to work.


```bash
aws iam list-open-id-connect-providers \
  --profile mds-devsecops-lab \
  --query 'OpenIDConnectProviderList[].Arn' \
  --output table
```


```bash
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --profile mds-devsecops-lab \
  --no-cli-pager
```


```bash
aws iam get-open-id-connect-provider \
  --open-id-connect-provider-arn arn:aws:iam::YOUR_ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com \
  --profile mds-devsecops-lab \
  --query '{Url:Url,ClientIDList:ClientIDList}' \
  --output json
```


```bash
cd ~/projects/project-3-secure-cicd-pipeline
set -euo pipefail

aws iam create-role \
  --role-name project-3-terraform-plan-role \
  --assume-role-policy-document file://iam/terraform-github-oidc/plan-trust.json \
  --description "GitHub Actions OIDC role for Terraform planning" \
  --profile mds-devsecops-lab \
  --no-cli-pager

aws iam create-role \
  --role-name project-3-terraform-apply-role \
  --assume-role-policy-document file://iam/terraform-github-oidc/apply-trust.json \
  --description "GitHub Actions OIDC role for approved Terraform applies" \
  --profile mds-devsecops-lab \
  --no-cli-pager
```


```bash
cd ~/projects/project-3-secure-cicd-pipeline
set -euo pipefail

for policy in \
  iam/terraform-github-oidc/plan-permissions.json \
  iam/terraform-github-oidc/apply-permissions.json
do
  echo "Validating $policy"
  aws accessanalyzer validate-policy \
    --policy-type IDENTITY_POLICY \
    --policy-document "file://$policy" \
    --profile mds-devsecops-lab \
    --region us-east-1 \
    --query 'findings[].{Type:findingType,Code:issueCode,Details:findingDetails}' \
    --output json \
    --no-cli-pager
done
```


```bash
cd ~/projects/project-3-secure-cicd-pipeline
set -euo pipefail

aws iam put-role-policy \
  --role-name project-3-terraform-plan-role \
  --policy-name project-3-terraform-plan-policy \
  --policy-document file://iam/terraform-github-oidc/plan-permissions.json \
  --profile mds-devsecops-lab \
  --no-cli-pager

aws iam put-role-policy \
  --role-name project-3-terraform-apply-role \
  --policy-name project-3-terraform-apply-policy \
  --policy-document file://iam/terraform-github-oidc/apply-permissions.json \
  --profile mds-devsecops-lab \
  --no-cli-pager

aws iam list-role-policies \
  --role-name project-3-terraform-plan-role \
  --profile mds-devsecops-lab \
  --output table

aws iam list-role-policies \
  --role-name project-3-terraform-apply-role \
  --profile mds-devsecops-lab \
  --output table
```


```bash
gh variable set TF_STATE_BUCKET \
  --repo DelaneKay/project-3-secure-cicd-pipeline \
  --body "project-3-tfstate-YOUR_ACCOUNT_ID-us-east-1"

gh variable set AWS_TERRAFORM_PLAN_ROLE_ARN \
  --repo DelaneKay/project-3-secure-cicd-pipeline \
  --body "arn:aws:iam::YOUR_ACCOUNT_ID:role/project-3-terraform-plan-role"

gh variable set AWS_TERRAFORM_APPLY_ROLE_ARN \
  --repo DelaneKay/project-3-secure-cicd-pipeline \
  --body "arn:aws:iam::YOUR_ACCOUNT_ID:role/project-3-terraform-apply-role"
```

## 18. Configure deployment approval and runner registration

The protected environment introduced a review point before infrastructure changes. A GitHub App supplied short-lived registration credentials for a new runner without putting a permanent token in an AMI.

In GitHub Settings → Environments, I created `terraform-lab-apply`, restricted deployment to `master`, added `DelaneKay` as required reviewer, left Prevent self-review unchecked for this solo lab, disabled administrator bypass and saved. I reviewed each readable Terraform plan before approving its saved-plan apply. These were browser actions, so I do not invent a terminal command that claims to have performed them.


```bash
gh variable set TF_STATE_BUCKET \
  --repo DelaneKay/project-3-secure-cicd-pipeline \
  --body "project-3-tfstate-YOUR_ACCOUNT_ID-us-east-1"

gh variable set AWS_TERRAFORM_PLAN_ROLE_ARN \
  --repo DelaneKay/project-3-secure-cicd-pipeline \
  --body "arn:aws:iam::YOUR_ACCOUNT_ID:role/project-3-terraform-plan-role"

gh variable set AWS_TERRAFORM_APPLY_ROLE_ARN \
  --repo DelaneKay/project-3-secure-cicd-pipeline \
  --body "arn:aws:iam::YOUR_ACCOUNT_ID:role/project-3-terraform-apply-role"
```

I also created a GitHub App, selected only this repository, granted repository Administration write, generated its PEM key and installed it. I stored `RUNNER_GITHUB_APP_ID` and `RUNNER_GITHUB_APP_PRIVATE_KEY` as Actions secrets, never in Git. The workflow creates a short-lived registration token, places it in SSM SecureString, and the new runner consumes it at first boot. The exact implementation is in [terraform-layer.yml](../.github/workflows/terraform-layer.yml); I inspect the workflow rather than manually placing a registration token in Terraform state.

## 19. Run the standalone Terraform deployment and verify AWS resources

I tested infrastructure deployment on its own before calling it from the combined pipeline. The scanner runner and SonarQube platform must exist before application scans can use them.

I first ran `Terraform deployment` on `master`, approved the layer plans and checked the resulting EC2 and RDS resources. Networking applied first, then database and observability could progress independently; compute and SonarQube waited for their required upstream state. A first deployment needs this ordering because outputs do not exist before the upstream apply.


```bash
cd ~/projects/project-3-secure-cicd-pipeline

aws sts get-caller-identity \
  --profile mds-devsecops-lab

aws ec2 describe-instances \
  --profile mds-devsecops-lab \
  --region us-east-1 \
  --filters "Name=tag:Project,Values=project-3-secure-cicd-pipeline" \
            "Name=instance-state-name,Values=pending,running,stopping,stopped" \
  --query 'Reservations[].Instances[].{Name:Tags[?Key==`Name`]|[0].Value,InstanceId:InstanceId,State:State.Name,Type:InstanceType,PrivateIP:PrivateIpAddress}' \
  --output table

aws rds describe-db-instances \
  --profile mds-devsecops-lab \
  --region us-east-1 \
  --db-instance-identifier project-3-sonarqube \
  --query 'DBInstances[].{Status:DBInstanceStatus,Class:DBInstanceClass,Endpoint:Endpoint.Address,Encrypted:StorageEncrypted}' \
  --output table
```


```bash
aws ssm describe-instance-information \
  --profile mds-devsecops-lab \
  --region us-east-1 \
  --query 'InstanceInformationList[].{InstanceId:InstanceId,PingStatus:PingStatus,Platform:PlatformName}' \
  --output table
```

In GitHub I used Actions → Terraform deployment → Run workflow → master. The later combined pipeline reuses this deployment workflow. A green Terraform job proves resource operations succeeded; I still checked the application and SonarQube health separately.

## 20. Preserve immutability when a service fails

I kept the immutable rule during troubleshooting: diagnose, change the Packer source, rebuild and replace. The permission commands below belong in the temporary image build, not on the deployed host as a repair.

SonarQube repeatedly failed to listen on port 9000 even when systemd reported activating. I used SSM for read-only diagnostics, fixed the Packer source, rebuilt an AMI and let Terraform replace the instance. I did not turn a successful diagnosis into a permanent patch on the deployed server. These permission commands belong inside the image build, followed by the non-root execution test.


```bash
chown -R root:root /usr/local/aws-cli
chmod -R a+rX,u+w,go-w /usr/local/aws-cli
```


```bash
runuser -u sonarqube -- /bin/bash -c \
  'test -x /usr/local/aws-cli/v2/current/bin/aws &&
   /usr/local/aws-cli/v2/current/bin/aws --version'
```


```bash
cd ~/projects/project-3-secure-cicd-pipeline

git switch master
git pull --ff-only

aws sts get-caller-identity \
  --profile project-3-packer \
  --query Arn \
  --output text
```


```bash
AWS_PROFILE=project-3-packer packer build \
  -var 'source_ami_id=ami-REPLACE_WITH_YOUR_ID' \
  -var 'subnet_id=subnet-REPLACE_WITH_YOUR_ID' \
  -var 'security_group_id=sg-REPLACE_WITH_YOUR_ID' \
  -var 'sonarqube_version=26.10.0.133078' \
  -var 'java_package=openjdk-21-jdk' \
  packer/sonarqube/
```

The final successful SonarQube AMI recorded in this sequence was `ami-REPLACE_WITH_YOUR_ID`. Its replacement reported service `active` and API status `UP`. Reading tags/secrets at boot is part of the baked startup contract; packages, helper scripts and service definitions are baked before deployment. The AWS API can still fail at runtime, so a successful image build alone is not a full end-to-end health check.

## 21. Record rebuilt images and replace, rather than edit, the runner

I used replacement for missing tools, executable permissions and runner sizing. The lasting correction belonged in the image or Terraform definition, not in manual changes to a working server.

I encountered the same AWS CLI permission problem on the scanner runner, then discovered Node.js/npm were absent. I corrected the runner image, rebuilt it, recorded its AMI and backing snapshot, and replaced the EC2 runner through Terraform. The new runner used `ami-REPLACE_WITH_YOUR_ID`; the old offline GitHub runner entries were historical registrations, not usable capacity.


```bash
cd ~/projects/project-3-secure-cicd-pipeline

git switch master
git pull --ff-only
```


```bash
set -a
source packer/github-runner/versions.env
set +a

AWS_PROFILE=project-3-packer packer build \
  -var 'source_ami_id=ami-REPLACE_WITH_YOUR_ID' \
  -var 'subnet_id=subnet-REPLACE_WITH_YOUR_ID' \
  -var 'security_group_id=sg-REPLACE_WITH_YOUR_ID' \
  -var "github_runner_version=$GITHUB_RUNNER_VERSION" \
  -var "gitleaks_version=$GITLEAKS_VERSION" \
  -var "sonar_scanner_version=$SONAR_SCANNER_VERSION" \
  -var "dependency_check_version=$DEPENDENCY_CHECK_VERSION" \
  -var "zap_version=$ZAP_VERSION" \
  -var "terraform_version=$TERRAFORM_VERSION" \
  -var "aws_cli_version=$AWS_CLI_VERSION" \
  -var "java_package=$JAVA_PACKAGE" \
  packer/github-runner/
```


```bash
aws ec2 describe-images \
  --profile mds-devsecops-lab \
  --region us-east-1 \
  --image-ids ami-REPLACE_WITH_YOUR_ID \
  --query 'Images[].{AMI:ImageId,State:State,Snapshot:BlockDeviceMappings[0].Ebs.SnapshotId}' \
  --output table
```


```bash
cd ~/projects/project-3-secure-cicd-pipeline

git switch -c feat/runner-node-npm-ami

cat > packer/github-runner/ami-id.txt <<'EOF'
AMI_ID=ami-REPLACE_WITH_YOUR_ID
SNAPSHOT_ID=snap-REPLACE_WITH_YOUR_ID
AWS_REGION=us-east-1
EOF

git add packer/github-runner/ami-id.txt
git diff --cached --check
git commit -m "Record runner AMI with Node.js and npm"
git push -u origin feat/runner-node-npm-ami
```


```bash
gh pr create \
  --base master \
  --head feat/runner-node-npm-ami \
  --title "Record runner AMI with Node.js and npm" \
  --body "Record the rebuilt scanner runner AMI and its backing snapshot."
```


```bash
aws ec2 describe-instances \
  --profile mds-devsecops-lab \
  --region us-east-1 \
  --filters \
    "Name=tag:Name,Values=project-3-secure-cicd-pipeline-scanner-runner" \
    "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].{Instance:InstanceId,AMI:ImageId,Type:InstanceType,PrivateIP:PrivateIpAddress}' \
  --output table
```


```bash
gh api repos/DelaneKay/project-3-secure-cicd-pipeline/actions/runners \
  --jq '.runners[] | {name, status, busy}'
```


```bash
COMMAND_ID=$(aws ssm send-command \
  --profile mds-devsecops-lab \
  --region us-east-1 \
  --instance-ids i-REPLACE_WITH_YOUR_ID \
  --document-name AWS-RunShellScript \
  --parameters '{"commands":["runuser -u actions-runner -- /usr/local/bin/node --version","runuser -u actions-runner -- /usr/local/bin/npm --version","runuser -u actions-runner -- /usr/local/bin/dependency-check --version"]}' \
  --query 'Command.CommandId' \
  --output text) && printf '%s\n' "$COMMAND_ID"
```


```bash
aws ssm get-command-invocation \
  --profile mds-devsecops-lab \
  --region us-east-1 \
  --command-id 5bd01d7f-c80e-4a73-9f11-e34c94f1a077 \
  --instance-id i-REPLACE_WITH_YOUR_ID \
  --query '{Status:Status,Output:StandardOutputContent,Errors:StandardErrorContent}' \
  --output json
```

The verification output was Node.js `v22.23.4`, npm `10.9.9` and Dependency-Check `13.0.0`. I also replaced the original 2 GB `t3.small` runner with `c7i-flex.large` after the kernel OOM evidence. The Terraform plan had to show replacement, not an in-place stop/resize operation.

## 22. Run Gitleaks separately on the AWS runner

Gitleaks checked repository history for possible secrets before I progressed to application analysis. This covers a different risk from vulnerable packages or web responses.

I ran Gitleaks on the self-hosted scanner after it registered online. I scanned full Git history and uploaded a redacted JSON report. The first finding was the public AWS CLI signing-key fingerprint; I examined the exact historical commit before adding a single-finding ignore entry. I did not disable the generic API-key rule globally.


```bash
gh workflow run gitleaks-aws.yml --ref master

gh run list --workflow gitleaks-aws.yml --limit 3
```


```bash
gh run watch 41624217203 --exit-status
```


```bash
gh run view 41624217203
```


```bash
git show 9d2406ca349dfe9ad1aac51dedc80129a819c226:packer/sonarqube/scripts/install-sonarqube.sh \
  | sed -n '9p' \
  | cut -d= -f1
```


```bash
cd ~/projects/project-3-secure-cicd-pipeline
git switch -c fix/gitleaks-public-key-fingerprint

cat >> .gitleaksignore <<'EOF'
# AWS CLI public signing-key fingerprint used for package signature verification.
9d2406ca349dfe9ad1aac51dedc80129a819c226:packer/sonarqube/scripts/install-sonarqube.sh:generic-api-key:9
EOF

git diff -- .gitleaksignore
git status --short
```


```bash
git add .gitleaksignore
git diff --cached --check
git commit -m "Exclude verified public AWS CLI signing fingerprint"
git push -u origin fix/gitleaks-public-key-fingerprint
```


```bash
gh pr create \
  --base master \
  --head fix/gitleaks-public-key-fingerprint \
  --title "Exclude public AWS CLI signing fingerprint from Gitleaks" \
  --body "Document and suppress one verified false positive using its exact commit, file, rule, and line. The value is the public AWS CLI signing-key fingerprint used for package verification."
```


```bash
gh workflow run gitleaks-aws.yml --ref master
gh run list --workflow gitleaks-aws.yml --limit 3
```


```bash
gh run watch 41626050135 --exit-status

gh run download 41626050135 \
  --dir reports/gitleaks-41626050135

find reports/gitleaks-41626050135 -name 'gitleaks.json' -exec cat {} \;
```

The verified rerun returned `[]`. Vulnerability findings remain report-only, while a missing executable or missing report is a scanner failure. The [Gitleaks workflow](../.github/workflows/gitleaks-aws.yml) contains the checked-in scan and report steps.

## 23. Open SonarQube through SSM and bootstrap its project

SonarQube provided a central source-analysis project, rule profiles and a results API. Its project setup is application-level configuration through a supported API, not a change to the host's baked software.

I forwarded port 9000 to localhost with SSM, logged in to SonarQube and changed its initial password. I created the protected `sonarqube-admin` GitHub environment with `SONAR_HOST_URL` and `SONAR_ADMIN_TOKEN`, then ran the project setup workflow on the AWS runner. The setup script creates/reconciles the private `project-3-juice-shop` project and discovers the built-in language defaults.


```bash
aws ssm start-session \
  --profile mds-devsecops-lab \
  --region us-east-1 \
  --target i-REPLACE_WITH_YOUR_ID \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["9000"],"localPortNumber":["9000"]}'
```


```bash
cd ~/projects/project-3-secure-cicd-pipeline

gh workflow run sonarqube-setup.yml --ref master
gh run list --workflow sonarqube-setup.yml --limit 3
```

I used `http://localhost:9000/projects` in my browser. A version-specific profile-name mismatch initially failed setup: this release offered `Sonar way core`, `extended` and `comprehensive`, not a single profile literally named `Sonar way`. The corrected setup selected the language's built-in default. The next setup run succeeded without a host change or AMI rebuild.

## 24. Separate SonarQube analysis and reporting permissions

I separated analysis and reporting identities because submitting analysis and reading results are different jobs. Routine reporting did not need administrator permissions.

I created `sonarqube-scan`, set `SONAR_HOST_URL` to the reachable private SonarQube URL, and stored the project analysis token as `SONAR_TOKEN`. I created `project-3-reporter`, granted Browse only at `http://localhost:9000/project_roles?id=project-3-juice-shop`, and stored that account's user token as `SONAR_REPORT_TOKEN`. A token inherits its owner's permissions; I did not use the administrator token for routine reporting.


```bash
gh workflow run sonarqube-analysis.yml --ref master

gh run list --workflow sonarqube-analysis.yml --limit 3
```


```bash
gh run watch 41648646890 --exit-status
```


```bash
gh run view 41648646890
```


```bash
gh run view 41648646890 --log-failed
```

The workflow checked out Juice Shop v20.3.0, submitted analysis and kept quality-gate findings report-only. The later export step waited for processing and saved issue summaries and the analysis receipt. A screenshot once displayed a token; reusable documentation must not preserve token values. Account/token creation was performed in the UI, not by an invented shell command.

## 25. Export SonarQube results and verify CloudWatch/SNS

CloudWatch and SNS made the results visible beyond a job log. I stored detailed reports as artifacts and published aggregate summaries to avoid one email per issue.

I added the reporting step only after the standalone analysis worked. I downloaded the report to inspect its summary and verified a CloudWatch stream. SNS initially had no subscriptions, so successful publish calls could not produce an email. I supplied `TF_NOTIFICATION_EMAIL` through the repository variable, applied observability through the workflow, confirmed AWS's subscription email, and reran analysis.


```bash
gh workflow run sonarqube-analysis.yml --ref master

gh run list --workflow sonarqube-analysis.yml --limit 3
```


```bash
gh run watch 41671030481 --exit-status
```


```bash
gh run view 41671030481 --log-failed
```


```bash
gh run download 41671030481 \
  --name sonarqube-results \
  --dir reports/sonarqube-41671030481

cat reports/sonarqube-41671030481/summary.json
```


```bash
aws sns list-subscriptions-by-topic \
  --profile mds-devsecops-lab \
  --region us-east-1 \
  --topic-arn arn:aws:sns:us-east-1:YOUR_ACCOUNT_ID:project-3-secure-cicd-pipeline-scan-findings \
  --query 'Subscriptions[].{Protocol:Protocol,Status:SubscriptionArn}' \
  --output table
```


```bash
aws logs describe-log-streams \
  --profile mds-devsecops-lab \
  --region us-east-1 \
  --log-group-name /project-3/pipeline/scans \
  --log-stream-name-prefix sonarqube-41671030481 \
  --query 'logStreams[].{Stream:logStreamName,LastEvent:lastEventTimestamp}' \
  --output table
```


```bash
cd ~/projects/project-3-secure-cicd-pipeline

grep -n -i 'notification_email' \
  terraform/observability/variables.tf \
  .github/workflows/terraform-layer.yml \
  .github/workflows/terraform-deploy.yml
```


```bash
aws sns list-subscriptions-by-topic \
  --profile mds-devsecops-lab \
  --region us-east-1 \
  --topic-arn arn:aws:sns:us-east-1:YOUR_ACCOUNT_ID:project-3-secure-cicd-pipeline-scan-findings \
  --output json --no-cli-pager
```


```bash
gh workflow run sonarqube-analysis.yml --ref master

gh run list --workflow sonarqube-analysis.yml --limit 3
```


```bash
gh run watch 41695305784 --exit-status
```

The summary contained 272 SonarQube issues: 104 blocker, 10 critical, 96 major and 62 minor. These are SonarQube issue severities, not proof of 272 exploitable vulnerabilities. The quality status was `OK`. CloudWatch receives one aggregate event and SNS one concise summary per scan attempt, while full findings stay in report artifacts.

## 26. Run Dependency-Check separately

Dependency-Check added known-vulnerability analysis of the packaged dependencies. I checked its input and vulnerability-data access before trusting its findings.

I verified Node.js, npm and Dependency-Check as the runner account before starting SCA. I created the `dependency-check` GitHub environment and stored `NVD_API_KEY` there. The initial source-tree workflow expected a top-level lockfile that was absent from the selected release; I changed it to verify and scan the packaged Juice Shop release with its installed dependencies.


```bash
COMMAND_ID=$(aws ssm send-command \
  --profile mds-devsecops-lab \
  --region us-east-1 \
  --instance-ids i-REPLACE_WITH_YOUR_ID \
  --document-name AWS-RunShellScript \
  --parameters '{"commands":["runuser -u actions-runner -- /usr/local/bin/node --version","runuser -u actions-runner -- /usr/local/bin/npm --version","runuser -u actions-runner -- /usr/local/bin/dependency-check --version"]}' \
  --query 'Command.CommandId' \
  --output text) && printf '%s\n' "$COMMAND_ID"
```


```bash
aws ssm get-command-invocation \
  --profile mds-devsecops-lab \
  --region us-east-1 \
  --command-id 5bd01d7f-c80e-4a73-9f11-e34c94f1a077 \
  --instance-id i-REPLACE_WITH_YOUR_ID \
  --query '{Status:Status,Output:StandardOutputContent,Errors:StandardErrorContent}' \
  --output json
```


```bash
gh run list --workflow dependency-check.yml --limit 3
```


```bash
gh run view 41719010612 --log-failed
```


```bash
gh run download 41719010612 \
  --name dependency-check-results \
  --dir reports/dependency-check-41719010612

python3 - <<'PY'
import json
from pathlib import Path

path = Path("reports/dependency-check-41719010612/dependency-check-report.json")
report = json.loads(path.read_text())

print("Top-level report fields:", ", ".join(report.keys()))
print("Analysis exceptions:", json.dumps(report.get("analysisExceptions", []), indent=2))
print("Dependencies reported:", len(report.get("dependencies", [])))
PY
```

In GitHub I selected Actions → Juice Shop Dependency-Check → Run workflow → master. The packaged release checksum was checked before extraction. The final workflow disables npm/yarn/pnpm audit for this artifact and uses the NVD-backed CPE analysis plus the other enabled analyzers. I report `completed_limited_coverage`, because a packaged dependency tree without the top-level lockfile does not provide complete package-audit coverage.

## 27. Fix Dependency-Check execution before trusting its findings

Report-only findings did not excuse a failed scanner. I corrected the workflow configuration and reran it rather than accepting an incomplete report as a clean result.

The missing NVD key failed updates with exit 13. A later run wrote reports but still ended with unexpected exceptions and exit 14; that was not a clean scan. I inspected the report and added sanitized exception diagnostics. The confirmed parser correction changed the empty CPE skip-list property to an explicit empty JSON array.


```text
ecosystem.skip.cpeanalyzer=
```


```properties
ecosystem.skip.cpeanalyzer=[]
```


```bash
gh run download 41719010612 \
  --name dependency-check-results \
  --dir reports/dependency-check-41719010612

python3 - <<'PY'
import json
from pathlib import Path

path = Path("reports/dependency-check-41719010612/dependency-check-report.json")
report = json.loads(path.read_text())

print("Top-level report fields:", ", ".join(report.keys()))
print("Analysis exceptions:", json.dumps(report.get("analysisExceptions", []), indent=2))
print("Dependencies reported:", len(report.get("dependencies", [])))
PY
```

The final recorded summary reported 16,284 dependencies, 20 vulnerable dependencies and 66 vulnerability occurrences: critical 23, high 13, medium 24 and low 6. Counts can change as vulnerability data changes. The [Dependency-Check workflow](../.github/workflows/dependency-check.yml) contains the scan command, NVD key handling and execution diagnostics.

## 28. Verify ZAP and target reachability before DAST

DAST needs a running reachable target. These read-only checks verified the tools already baked into the runner; missing software would have required an image rebuild.

I checked the installed ZAP launcher and automation add-on as `actions-runner`. My first attempt used a nonexistent user called `runner`; that was an account-name mistake, not a reason to create a new user on the deployed host. I then checked the running Juice Shop instance and HTTP reachability from the scanner.


```bash
aws ssm send-command \
  --profile mds-devsecops-lab \
  --region us-east-1 \
  --instance-ids i-REPLACE_WITH_YOUR_ID \
  --document-name AWS-RunShellScript \
  --parameters 'commands=["command -v zap.sh || command -v zap || true","ls -d /opt/*zap* /opt/*ZAP* 2>/dev/null || true"]' \
  --query 'Command.CommandId' \
  --output text
```


```bash
aws ssm get-command-invocation \
  --profile mds-devsecops-lab \
  --region us-east-1 \
  --command-id d24cf239-195f-40ad-bd05-7a9b6037e34d \
  --instance-id i-REPLACE_WITH_YOUR_ID \
  --query '{Status:Status,Output:StandardOutputContent,Errors:StandardErrorContent}' \
  --output json
```


```bash
aws ssm send-command \
  --profile mds-devsecops-lab \
  --region us-east-1 \
  --instance-ids i-REPLACE_WITH_YOUR_ID \
  --document-name AWS-RunShellScript \
  --parameters 'commands=["runuser -u actions-runner -- /usr/local/bin/zap.sh -version"]' \
  --query 'Command.CommandId' \
  --output text
```


```bash
aws ssm get-command-invocation \
  --profile mds-devsecops-lab \
  --region us-east-1 \
  --command-id 1e86f2b0-ec76-42d0-a894-99d8a2e534b0 \
  --instance-id i-REPLACE_WITH_YOUR_ID \
  --query '{Status:Status,Output:StandardOutputContent,Errors:StandardErrorContent}' \
  --output json
```


```bash
aws ec2 describe-instances \
  --profile mds-devsecops-lab \
  --region us-east-1 \
  --filters \
    "Name=tag:Name,Values=project-3-secure-cicd-pipeline-juice-shop" \
    "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].{Instance:InstanceId,PrivateIP:PrivateIpAddress,State:State.Name}' \
  --output table
```


```bash
aws ssm send-command \
  --profile mds-devsecops-lab \
  --region us-east-1 \
  --instance-ids i-REPLACE_WITH_YOUR_ID \
  --document-name AWS-RunShellScript \
  --parameters 'commands=["curl --connect-timeout 5 --silent --show-error --output /dev/null --write-out \"Juice Shop HTTP %{http_code}\\n\" http://PRIVATE_HOST_IP:3000/"]' \
  --query 'Command.CommandId' \
  --output text
```


```bash
aws ssm get-command-invocation \
  --profile mds-devsecops-lab \
  --region us-east-1 \
  --command-id ef818084-33c1-4bd4-940a-8fc3bcb6a4ed \
  --instance-id i-REPLACE_WITH_YOUR_ID \
  --query '{Status:Status,Output:StandardOutputContent,Errors:StandardErrorContent}' \
  --output json
```


```bash
aws ssm send-command \
  --profile mds-devsecops-lab \
  --region us-east-1 \
  --instance-ids i-REPLACE_WITH_YOUR_ID \
  --document-name AWS-RunShellScript \
  --parameters 'commands=["find /opt/project-3/tools -type f \\( -iname \"*automation*.zap\" -o -iname \"*automation*.jar\" \\) -print"]' \
  --query 'Command.CommandId' \
  --output text
```


```bash
aws ssm get-command-invocation \
  --profile mds-devsecops-lab \
  --region us-east-1 \
  --command-id c32db850-433a-4de7-a13a-674ddc47bb05 \
  --instance-id i-REPLACE_WITH_YOUR_ID \
  --query '{Status:Status,Output:StandardOutputContent,Errors:StandardErrorContent}' \
  --output json
```

The checks returned ZAP 2.17.0, the automation-beta 0.58.0 add-on and Juice Shop HTTP 200. These commands verified the installed image and network path; they did not install new host software.

## 29. Run ZAP separately and keep its scope bounded

ZAP tested the running application's HTTP behaviour after deployment. Target validation and bounded scan settings kept the active test within the approved lab.

I used Actions → Juice Shop ZAP DAST → Run workflow → master after merging its workflow. ZAP discovers exactly one running Project-tagged Juice Shop instance, checks the address is inside `10.20.0.0/16`, tests HTTP reachability, then runs a bounded unauthenticated spider and active scan. I limited the target to my lab application. The [ZAP workflow](../.github/workflows/zap-dast.yml) contains the scan command and automation plan.

The successful run was `41832567685`, with five alert types: two medium and three informational. It produced JSON/HTML reports and an SNS email. This is limited unauthenticated coverage: it does not claim to exercise all Juice Shop routes, JavaScript flows or authenticated features.

```bash
gh run view 41832567685
```

This uses the same `gh run view` command used throughout the lab, with the successful ZAP run ID shown in the recorded notification.

## 30. Combine the tested workflows without deleting the separate ones

Reusable workflows connected the tested controls without a second copy of their logic. The separate entry points remained useful for demonstrations and isolated troubleshooting.

After verifying Gitleaks, SAST, SCA and DAST independently, I added `workflow_call` to the reusable scanner/deployment workflows and created `secure-pipeline.yml`. The separate workflows remain available for demonstrations and isolated troubleshooting. The combined workflow starts Gitleaks, SonarQube and Dependency-Check before deployment, reuses reviewed Terraform deployment, and runs ZAP after deployment.


```yaml
name: Combined secure CI-CD pipeline
on:
  workflow_dispatch:
permissions:
  contents: read
  id-token: write
concurrency:
  group: project-3-combined-pipeline
  cancel-in-progress: false
jobs:
  gitleaks:
    name: Gitleaks secrets scan
    uses: ./.github/workflows/gitleaks-aws.yml

  sonarqube:
    name: SonarQube SAST
    uses: ./.github/workflows/sonarqube-analysis.yml
    secrets: inherit

  dependency_check:
    name: Dependency-Check SCA
    uses: ./.github/workflows/dependency-check.yml
    secrets: inherit

  deploy:
    name: Terraform reviewed deployment
    needs: [gitleaks, sonarqube, dependency_check]
    uses: ./.github/workflows/terraform-deploy.yml
    secrets: inherit

  zap:
    name: ZAP DAST
    needs: deploy
    uses: ./.github/workflows/zap-dast.yml
```

I used Actions → Combined secure CI-CD pipeline → Run workflow → master. This first combined run assumed the scanner and SonarQube platform already existed. It is not a cold-start bootstrap: a runner cannot execute scans before the runner exists. The complete standalone Terraform workflow remains the way I bring the platform up first.

## 31. Verify the combined run and preserve evidence

My first combined run, `41846334576`, completed successfully in 33 minutes 47 seconds with nine artifacts. Four were scanner result bundles and five were saved Terraform plan bundles. I retained the separate workflow files as well as the combined one. A green pipeline means the configured jobs completed; it does not mean the intentionally vulnerable application is safe.


```bash
mkdir -p ~/project-3-artifact-review

gh run download 41846334576 \
  --repo DelaneKay/project-3-secure-cicd-pipeline \
  --dir ~/project-3-artifact-review

find ~/project-3-artifact-review -type f | sort
```

The successful run is [available in Actions](https://github.com/DelaneKay/project-3-secure-cicd-pipeline/actions/runs/41846334576). I kept reviewed scanner evidence for the portfolio and did not publish binary Terraform plans/state as portfolio examples. Reports demonstrate what a particular run actually found; source code alone cannot prove the tools executed or the notification arrived.

### Verify the CloudWatch scan summaries

I used these read-only commands in WSL to check that the scanner summaries reached CloudWatch. The first query shows events from the last 24 hours; the second isolates the demonstrated combined run. [View my saved CloudWatch results](evidence/cloudwatch-scan-summaries.md), including the earlier execution failures and later Gitleaks findings, rather than relying on a successful workflow badge alone.

**Recent summary events:**

```bash
aws logs filter-log-events \
  --profile mds-devsecops-lab \
  --region us-east-1 \
  --log-group-name /project-3/pipeline/scans \
  --start-time "$(date -d '24 hours ago' +%s)000" \
  --query 'events[].{Stream:logStreamName,Summary:message}' \
  --output json \
  --no-cli-pager
```

**Summary events for combined run `41846334576`:**

```bash
aws logs filter-log-events \
  --profile mds-devsecops-lab \
  --region us-east-1 \
  --log-group-name /project-3/pipeline/scans \
  --filter-pattern '"41846334576"' \
  --query 'events[].{Stream:logStreamName,Summary:message}' \
  --output json \
  --no-cli-pager
```

The 24-hour window moves each time I run the first command, while the historical run query depends on the log retention period. An empty response is not evidence of zero vulnerabilities. I read the saved results in the linked file; detailed findings are in the linked report bundles.

### Open the saved pipeline results

I kept the results separate from the walkthrough so readers can inspect the evidence directly.

| Results | View or download |
| --- | --- |
| CloudWatch summaries, including failed executions and later scans | [View saved CloudWatch output](evidence/cloudwatch-scan-summaries.md) |
| Combined-run report index and coverage limitations | [View the evidence index](evidence/combined-run-41846334576/README.md) |
| Gitleaks | [Download ZIP](evidence/combined-run-41846334576/gitleaks.zip) |
| SonarQube | [Download ZIP](evidence/combined-run-41846334576/sonarqube.zip) |
| OWASP Dependency-Check | [Download ZIP](evidence/combined-run-41846334576/dependency-check.zip) |
| OWASP ZAP | [Download ZIP](evidence/combined-run-41846334576/zap.zip) |

The four ZIPs are archived scanner reports from combined run `41846334576`. They are point-in-time evidence, not the latest result for every scanner. I extract each ZIP to read its HTML, JSON or CSV files. Terraform binary plans and state are not included in these public evidence links.

## 32. Check the trust boundaries against the actual configuration

I checked the boundaries using the same identity, network, runner-registration and subscription queries I used during the build. Each boundary below identifies who may cross it and which control makes that possible.


```bash
export AWS_PROFILE=mds-devsecops-lab
export AWS_REGION=us-east-1
export AWS_DEFAULT_REGION=us-east-1

aws sts get-caller-identity
packer version
```


```bash
aws ec2 describe-vpcs \
  --profile mds-devsecops-lab \
  --region us-east-1 \
  --filters "Name=tag:Project,Values=project-3-secure-cicd-pipeline" \
  --query 'Vpcs[].{VpcId:VpcId,Cidr:CidrBlock}' \
  --output table
```


```bash
aws ec2 describe-subnets \
  --profile mds-devsecops-lab \
  --region us-east-1 \
  --filters "Name=vpc-id,Values=vpc-REPLACE_WITH_YOUR_ID" \
  --query 'Subnets[].{SubnetId:SubnetId,AZ:AvailabilityZone,Cidr:CidrBlock}' \
  --output table

aws ec2 describe-security-groups \
  --profile mds-devsecops-lab \
  --region us-east-1 \
  --filters "Name=vpc-id,Values=vpc-REPLACE_WITH_YOUR_ID" \
  --query 'SecurityGroups[].{GroupId:GroupId,Name:GroupName}' \
  --output table
```


```bash
gh api repos/DelaneKay/project-3-secure-cicd-pipeline/actions/runners \
  --jq '.runners[] | {name, status, busy}'
```


```bash
aws sns list-subscriptions-by-topic \
  --profile mds-devsecops-lab \
  --region us-east-1 \
  --topic-arn arn:aws:sns:us-east-1:YOUR_ACCOUNT_ID:project-3-secure-cicd-pipeline-scan-findings \
  --output json --no-cli-pager
```

| Boundary | What crosses it | Control I used |
| --- | --- | --- |
| WSL operator → AWS | Human bootstrap and role assumption | Short-lived login session; explicit profile and STS identity check |
| GitHub → AWS planning | OIDC token for trusted master job | Plan role trust with repository subject and audience |
| GitHub → AWS apply | Approved saved-plan deployment | Separate apply role; protected `terraform-lab-apply`; saved-plan checksum |
| One Terraform root → another | Upstream outputs | Separate S3 state keys; explicit workflow dependencies |
| Terraform process → state backend | State writes and locks | Private encrypted/versioned bucket; scoped state/lock permissions; concurrency |
| Packer operator → temporary builder | Image provisioning | Builder profile, SSM tunnel, no inbound SG rules |
| GitHub → AWS scanner runner | Trusted workflow job | Repository-scoped registration, scanner label, master-only job conditions |
| Scanner → SonarQube | Analysis and result API calls | Private port 9000 path; project analysis token; separate Browse-only reporter |
| SonarQube → RDS | PostgreSQL credentials and traffic | SonarQube runtime role, secret read scope; database SG source restricted to SonarQube |
| Host → AWS services | SSM, secrets and logging requests | Runtime IAM roles, IMDSv2 and selected VPC endpoints |
| Scanner → Juice Shop | Authorized HTTP/DAST traffic | Target tag/address validation, port 3000 SG rule and bounded scope |
| Scanners → CloudWatch/SNS | Aggregate summaries | Runner role scoped to the lab log group/topic; confirmed email subscription |
| Pipeline → portfolio reader | Evidence | Redacted scan reports; no private keys, tokens, state or binary plans |

The private SonarQube/scanner HTTP API path still uses HTTP inside the VPC; private addressing is not TLS. The reused scanner runner is also not a fresh isolated machine per job. I retain these as lab limitations rather than describing them as solved production controls.

## 33. Destroy through the workflow and verify what remains

When I paused the lab I used Terraform destroy through GitHub, not manual deletion of state files. In Actions → Terraform destroy → Run workflow, I selected master, supplied the workflow's required `DESTROY` confirmation, reviewed the destroy plans and approved them. Destruction runs in reverse dependency order. My RDS configuration skips the final snapshot as agreed.


```bash
aws sts get-caller-identity --profile mds-devsecops-lab

aws ec2 describe-instances \
  --profile mds-devsecops-lab --region us-east-1 \
  --filters "Name=tag:Project,Values=project-3-secure-cicd-pipeline" \
            "Name=instance-state-name,Values=pending,running,stopping,stopped" \
  --query 'Reservations[].Instances[].{Id:InstanceId,Name:Tags[?Key==`Name`]|[0].Value,State:State.Name}' \
  --output table

aws rds describe-db-instances \
  --profile mds-devsecops-lab --region us-east-1 \
  --query "DBInstances[?starts_with(DBInstanceIdentifier, 'project-3')].{Id:DBInstanceIdentifier,Status:DBInstanceStatus}" \
  --output table

aws ec2 describe-vpcs \
  --profile mds-devsecops-lab --region us-east-1 \
  --filters "Name=tag:Project,Values=project-3-secure-cicd-pipeline" \
  --query 'Vpcs[].{Id:VpcId,State:State}' \
  --output table
```

I expected no active Project 3 instances, database or VPC after a complete teardown. Terraform destruction does not remove the bootstrap state bucket, Packer AMIs/backing snapshots or bootstrap IAM roles. AMI snapshots are required image backing storage; they are separate from the optional final RDS snapshot we disabled. I retained the AMIs to rebuild the lab later.

## 34. Challenge: stale VPC/subnet permissions after recreation

This manual IAM-policy repair exposed a remaining bootstrap automation gap. It did not change a deployed host, and I returned to workflow deployment after correcting the policy.

The EC2 403s persisted because the role policy referred to a previous network. I compared the live VPC/subnets with `LaunchInterfacesInLabVpc`, `LaunchInTaggedSubnets` and `UseTaggedLabSecurityGroups`. I updated those exact conditions, reviewed the JSON and reapplied the bootstrap IAM policy. This was a bootstrap policy repair, not a patch to the deployed machines.


```bash
aws ec2 describe-vpcs \
  --profile mds-devsecops-lab \
  --region us-east-1 \
  --filters "Name=tag:Project,Values=project-3-secure-cicd-pipeline" \
  --query 'Vpcs[].{VpcId:VpcId,Cidr:CidrBlock}' \
  --output table
```


```bash
aws ec2 describe-subnets \
  --profile mds-devsecops-lab \
  --region us-east-1 \
  --filters "Name=vpc-id,Values=vpc-REPLACE_WITH_YOUR_ID" \
  --query 'Subnets[].{SubnetId:SubnetId,AZ:AvailabilityZone,Cidr:CidrBlock}' \
  --output table

aws ec2 describe-security-groups \
  --profile mds-devsecops-lab \
  --region us-east-1 \
  --filters "Name=vpc-id,Values=vpc-REPLACE_WITH_YOUR_ID" \
  --query 'SecurityGroups[].{GroupId:GroupId,Name:GroupName}' \
  --output table
```


```bash
cd ~/projects/project-3-secure-cicd-pipeline
set -euo pipefail

policy="iam/terraform-github-oidc/apply-permissions.json"
region="us-east-1"
project="project-3-secure-cicd-pipeline"
profile="mds-devsecops-lab"

account_id="$(aws sts get-caller-identity \
  --profile "$profile" \
  --query Account --output text)"

vpc_ids="$(aws ec2 describe-vpcs \
  --filters "Name=tag:Project,Values=$project" \
  --query 'Vpcs[].VpcId' --output text \
  --profile "$profile" --region "$region")"

read -r -a vpcs <<< "$vpc_ids"
if [ "${#vpcs[@]}" -ne 1 ]; then
  echo "Expected one Project-tagged VPC; found ${#vpcs[@]}. Stopping." >&2
  exit 1
fi
vpc_id="${vpcs[0]}"

subnet_ids="$(aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$vpc_id" "Name=tag:Project,Values=$project" \
  --query 'Subnets[].SubnetId' --output text \
  --profile "$profile" --region "$region")"

read -r -a subnets <<< "$subnet_ids"
if [ "${#subnets[@]}" -ne 4 ]; then
  echo "Expected four Project-tagged subnets; found ${#subnets[@]}. Stopping." >&2
  exit 1
fi

python3 - "$policy" "$region" "$account_id" "$vpc_id" "${subnets[@]}" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
region, account, vpc_id = sys.argv[2:5]
subnets = sys.argv[5:]
policy = json.loads(path.read_text())

vpc_arn = f"arn:aws:ec2:{region}:{account}:vpc/{vpc_id}"
subnet_arns = sorted(
    f"arn:aws:ec2:{region}:{account}:subnet/{subnet_id}"
    for subnet_id in subnets
)

required = {
    "LaunchInTaggedSubnets",
    "UseTaggedLabSecurityGroups",
    "LaunchInterfacesInLabVpc",
}
found = set()

for statement in policy["Statement"]:
    sid = statement.get("Sid")
    if sid in required:
        statement["Condition"]["StringEquals"]["ec2:Vpc"] = vpc_arn
        if sid == "LaunchInterfacesInLabVpc":
            statement["Condition"]["StringEquals"]["ec2:Subnet"] = subnet_arns
        found.add(sid)

if found != required:
    raise SystemExit(f"Expected policy statements {sorted(required)}; found {sorted(found)}")

path.write_text(json.dumps(policy, indent=2) + "\n")
PY

jq empty "$policy"
wc -c "$policy"
git diff -- "$policy"
```


```bash
cd ~/projects/project-3-secure-cicd-pipeline
git pull --ff-only

aws iam put-role-policy \
  --role-name project-3-terraform-apply-role \
  --policy-name project-3-terraform-apply-policy \
  --policy-document file://iam/terraform-github-oidc/apply-permissions.json \
  --profile mds-devsecops-lab
```

The recorded script ends with `jq empty`; on my WSL session `jq` was missing. The Python JSON load/write had already run. I did not interpret the failed local validation command as proof that IAM had been updated. After applying, I checked `aws iam get-role-policy` and started a fresh workflow plan. The current design still requires reconciling this external IAM policy when the network is replaced; automatic subnet discovery in Terraform alone does not update an independently bootstrapped role policy.

## 35. Challenge: OIDC, API-specific IAM scopes and policy size

I corrected the workflow's authorization configuration rather than bypassing it with broad administrator access or changing application hosts. The corrected policy was followed by a fresh reviewed plan.

The first OIDC assumption failed because the trust subject did not match this repository's immutable owner/repository identifiers. I corrected the two trust files and updated the live roles. I subsequently repaired CloudWatch list scope, RDS subnet-group ARN, EC2 image ARN ownership and launch-time tagging permissions instead of attaching AdministratorAccess.


```bash
aws iam update-assume-role-policy \
  --role-name project-3-terraform-plan-role \
  --policy-document file://iam/terraform-github-oidc/plan-trust.json \
  --profile mds-devsecops-lab

aws iam update-assume-role-policy \
  --role-name project-3-terraform-apply-role \
  --policy-document file://iam/terraform-github-oidc/apply-trust.json \
  --profile mds-devsecops-lab
```


```bash
aws iam update-assume-role-policy \
  --role-name project-3-terraform-plan-role \
  --policy-document file://iam/terraform-github-oidc/plan-trust.json \
  --profile mds-devsecops-lab

aws iam update-assume-role-policy \
  --role-name project-3-terraform-apply-role \
  --policy-document file://iam/terraform-github-oidc/apply-trust.json \
  --profile mds-devsecops-lab
```


```bash
aws iam get-role \
  --role-name project-3-terraform-plan-role \
  --query 'Role.AssumeRolePolicyDocument' \
  --output json \
  --profile mds-devsecops-lab

aws iam get-role \
  --role-name project-3-terraform-apply-role \
  --query 'Role.AssumeRolePolicyDocument' \
  --output json \
  --profile mds-devsecops-lab
```


```bash
aws iam get-role-policy \
  --role-name project-3-terraform-apply-role \
  --policy-name project-3-terraform-apply-policy \
  --profile mds-devsecops-lab \
  --query PolicyDocument \
  --output json
```

For this repository the subjects include `DelaneKay@YOUR_GITHUB_OWNER_ID` and `project-3-secure-cicd-pipeline@YOUR_GITHUB_REPOSITORY_ID`; a reader must use their own actual token subject. The role's aggregate inline-policy quota was also reached. I reduced redundant statements; counting formatted file bytes alone had incorrectly suggested a policy was too large. The final check counted JSON characters excluding formatting whitespace. I did not split inline policies and pretend that bypassed their aggregate quota.

## 36. Challenge: state lock, existing database and stale saved plans

Unlocking abandoned state and importing an existing database were exceptional state-recovery operations. After verifying ownership and reconciling state, I returned to automated plan and apply; I did not disable locking.

An S3 412 indicated an existing lock, not a permission denial. I checked for another live apply before unlocking the specific abandoned database operation. The following is the historical recovery command with its original lock ID; I never run it without establishing that the owning operation has ended.


```bash
cd ~/projects/project-3-secure-cicd-pipeline
export AWS_PROFILE=mds-devsecops-lab

terraform -chdir=terraform/database init -input=false \
  -backend-config="bucket=project-3-tfstate-YOUR_ACCOUNT_ID-us-east-1" \
  -backend-config="key=project-3/database/terraform.tfstate" \
  -backend-config="region=us-east-1" \
  -backend-config="use_lockfile=true"

terraform -chdir=terraform/database force-unlock -force \
  e9ee033d-2216-4d43-80f9-90caa17e5152
```

A separate failure said the database subnet group already existed. I checked the real database and subnet group, then used the dedicated import workflow to put existing resources into the intended state. After a partial apply or import changed state, the saved plan was stale; I generated a new plan through a fresh deployment run and reviewed it again.

## 37. Challenge: diagnose startup and permission failures without mutable repair

I stopped at diagnosis on the deployed host. Even where a live permission change might have been quicker, the lasting fix went into Packer and I replaced the instance so the next deployment did not depend on an undocumented repair.

I distinguished a running EC2 instance from a healthy service. The useful diagnostics were service status/journal, HTTP checks and file-path execution permissions under the service account. The checks below exposed the CLI executable-path/traversal problem, which I corrected in the image source. I also learned that SSM shell commands are not guaranteed to use Bash: `set -o pipefail` failed under `/bin/sh`.


```bash
SONAR_DIAG_CMD=$(aws ssm send-command \
  --profile mds-devsecops-lab \
  --region us-east-1 \
  --instance-ids i-REPLACE_WITH_YOUR_ID \
  --document-name AWS-RunShellScript \
  --parameters 'commands=["systemctl status sonarqube.service --no-pager --full || true","journalctl -u sonarqube.service -n 100 --no-pager || true","sudo -u sonarqube test -r /opt/sonarqube/logs/sonar.log && tail -n 80 /opt/sonarqube/logs/sonar.log || true","sudo -u sonarqube test -r /opt/sonarqube/logs/web.log && tail -n 80 /opt/sonarqube/logs/web.log || true","sudo -u sonarqube test -r /opt/sonarqube/logs/es.log && tail -n 80 /opt/sonarqube/logs/es.log || true"]' \
  --query 'Command.CommandId' \
  --output text)

aws ssm get-command-invocation \
  --profile mds-devsecops-lab \
  --region us-east-1 \
  --command-id "$SONAR_DIAG_CMD" \
  --instance-id i-REPLACE_WITH_YOUR_ID \
  --query '{Status:Status,Output:StandardOutputContent,Errors:StandardErrorContent}' \
  --output json
```


```bash
cat > /tmp/project-3-sonar-cli-diagnostic.json <<'JSON'
{
  "commands": [
    "for p in /usr/local/aws-cli/v2/current/bin/aws /usr/local/bin/aws /usr/bin/aws; do if [ -e \"$p\" ] || [ -L \"$p\" ]; then ls -l \"$p\"; readlink -f \"$p\" || true; namei -l \"$p\" || true; if sudo -u sonarqube test -x \"$p\"; then echo \"sonarqube_can_execute=$p\"; else echo \"sonarqube_cannot_execute=$p\"; fi; else echo \"missing=$p\"; fi; done",
    "sudo -u sonarqube /usr/local/bin/aws --version 2>&1 || true",
    "ls -ld /usr/local/aws-cli /usr/local/aws-cli/v2 /usr/local/aws-cli/v2/current /usr/local/bin 2>&1 || true"
  ]
}
JSON

COMMAND_ID=$(aws ssm send-command \
  --profile mds-devsecops-lab \
  --region us-east-1 \
  --instance-ids i-REPLACE_WITH_YOUR_ID \
  --document-name AWS-RunShellScript \
  --parameters file:///tmp/project-3-sonar-cli-diagnostic.json \
  --query 'Command.CommandId' \
  --output text)

echo "$COMMAND_ID"
```


```bash
aws ssm get-command-invocation \
  --profile mds-devsecops-lab \
  --region us-east-1 \
  --command-id COMMAND_ID \
  --instance-id i-REPLACE_WITH_YOUR_ID \
  --query '{Status:Status,Output:StandardOutputContent,Errors:StandardErrorContent}' \
  --output json
```

A shell diagnostic ending in success can hide an earlier failed `curl` if a later command succeeds. I inspected both the returned status and stdout/stderr. I required `UP` from SonarQube's API after replacement; merely seeing systemd `activating` was not enough.

## 38. Challenge: delivery failure is not a clean scan

I applied the same rule to reporting failures: correct software permissions in Packer or reporting/IAM logic in version control, then rebuild or rerun. I did not keep an ad hoc change on the deployed runner as the solution.

SonarQube analysis succeeded but export failed when `actions-runner` could not execute AWS CLI. After the image permission fix, CloudWatch delivered its event. SNS still needed a confirmed subscription before email could arrive. I verified these stages separately instead of treating a missing email as proof of zero issues.


```bash
gh run download 41656129319 \
  --name sonarqube-results \
  --dir reports/sonarqube-41656129319

cat reports/sonarqube-41656129319/summary.json
```


```bash
COMMAND_ID=$(aws ssm send-command \
  --profile mds-devsecops-lab \
  --region us-east-1 \
  --instance-ids i-REPLACE_WITH_YOUR_ID \
  --document-name AWS-RunShellScript \
  --parameters '{"commands":["runuser -u actions-runner -- /usr/local/bin/aws --version","runuser -u actions-runner -- /usr/local/bin/aws sts get-caller-identity --region us-east-1 --query Arn --output text"]}' \
  --query 'Command.CommandId' \
  --output text) && printf '%s\n' "$COMMAND_ID"
```


```bash
aws ssm get-command-invocation \
  --profile mds-devsecops-lab \
  --region us-east-1 \
  --command-id 9db1245b-815a-4a22-96b7-49db6c766f4a \
  --instance-id i-REPLACE_WITH_YOUR_ID \
  --query '{Status:Status,Output:StandardOutputContent,Errors:StandardErrorContent}' \
  --output json
```


```bash
aws sns list-subscriptions-by-topic \
  --profile mds-devsecops-lab \
  --region us-east-1 \
  --topic-arn arn:aws:sns:us-east-1:YOUR_ACCOUNT_ID:project-3-secure-cicd-pipeline-scan-findings \
  --query 'Subscriptions[].{Protocol:Protocol,Status:SubscriptionArn}' \
  --output table
```


```bash
aws logs describe-log-streams \
  --profile mds-devsecops-lab \
  --region us-east-1 \
  --log-group-name /project-3/pipeline/scans \
  --log-stream-name-prefix sonarqube-41671030481 \
  --query 'logStreams[].{Stream:logStreamName,LastEvent:lastEventTimestamp}' \
  --output table
```


```bash
aws sns list-subscriptions-by-topic \
  --profile mds-devsecops-lab \
  --region us-east-1 \
  --topic-arn arn:aws:sns:us-east-1:YOUR_ACCOUNT_ID:project-3-secure-cicd-pipeline-scan-findings \
  --output json --no-cli-pager
```

I use three distinct outcomes: a completed scan with no findings, a completed scan with findings, and execution/reporting failure. Findings do not block deployment in this lab. A tool that cannot run, parse its report or deliver required reporting is an operational failure and remains visible. I tested the separate workflows first so I could identify these failures before combining them.


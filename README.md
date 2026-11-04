# Project 3 — My step-by-step secure CI/CD lab walkthrough

> Repository copy: AWS account/resource identifiers, internal host addresses, database endpoints and personal email addresses have been replaced with placeholders. I obtain their real values using the lookup commands shown before running the dependent command. These placeholders are not literal working AWS IDs.

I built this walkthrough from the commands, file contents, results and corrections in our lab conversation. I followed the command-led structure of my Project 2B walkthrough: where I worked, what I ran, what I expected, what failed, and how I checked the correction. The command numbers link to the full chronological [command history](docs/command-history.md); the complete file contents written through the GitHub integration are preserved in the [configuration record](docs/configuration-record.md).

**How to follow this:** the numbered steps are the successful path through the lab. The first Terraform deployment was manual; I later replaced routine local deployment with GitHub workflows. The historical command record deliberately retains earlier versions and failures. It is evidence, not a script to execute from top to bottom. I use the corrected files from the repository when reproducing the final build.

**Where commands run:** unless I say otherwise, I run Bash in WSL as the Linux user `devsecops`, from `~/projects/project-3-secure-cicd-pipeline`. Commands inside a Packer provisioner run on its temporary AWS builder. SSM diagnostics execute on the explicitly selected AWS instance. A GitHub `run:` block executes on the runner selected by that job. I do not paste Bash into PowerShell.

**Historical values:** account `YOUR_ACCOUNT_ID`, region `us-east-1`, AMI IDs, instance IDs, VPC IDs, subnet IDs, command IDs and workflow run IDs below are the values recorded in this lab. A reader using another account must substitute their own values and update account-specific trust policies. A recreated subnet or instance receives a new ID; I check the lookup output before using an old command. I never copy a historical lock ID into an unrelated unlock operation.

**Prerequisites already present at the start:** AWS CLI, Git and WSL access. I installed Packer and the Session Manager plugin during this conversation. Terraform was available by the time I initialized the first root. I have not invented a Terraform installation session or claimed it happened here.

## Contents

1. WSL, AWS identity and repository access
2. Packer prerequisites, roles and all three images
3. Separate Terraform roots and the original manual test
4. S3 state, OIDC, protected applies and automated deployment
5. Read-only service checks and immutable replacement
6. Separate Gitleaks, SonarQube, Dependency-Check and ZAP workflows
7. CloudWatch, SNS and evidence
8. Combined pipeline, trust boundaries, cleanup and challenges


## 1. Start my WSL project directory and verify my AWS identity

I started in WSL and selected the IAM user profile for `us-east-1`. My expected identity ended in `:user/mds-devsecops-lab`. A Linux prompt saying `root` describes the local shell user; `aws sts get-caller-identity` tells me the AWS identity. I checked the latter instead of assuming the two were the same.


[Chat command 55](docs/command-history.md#command-55) · transcript line 2385.


```bash
cd ~/projects
mkdir project-3-secure-cicd-pipeline
cd project-3-secure-cicd-pipeline
```


[Chat command 308](docs/command-history.md#command-308) · transcript line 9156.


```bash
aws login --profile mds-devsecops-lab
```


[Chat command 69](docs/command-history.md#command-69) · transcript line 2612.


```bash
export AWS_PROFILE=mds-devsecops-lab
export AWS_REGION=us-east-1
export AWS_DEFAULT_REGION=us-east-1

aws sts get-caller-identity
packer version
```

The existing directory was later replaced by a clone, so I did not run `mkdir` again on each visit. I kept root recovery outside the normal build and deployment process.

## 2. Install Packer and the Session Manager plugin

I installed Packer from HashiCorp's package repository and the local Session Manager plugin. The version checks returned Packer 1.16.2 and plugin 1.2.896.0 in the recorded session. A completed installer returning to the prompt is different from a command that is still waiting.


[Chat command 71](docs/command-history.md#command-71) · transcript line 2648.


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


[Chat command 72](docs/command-history.md#command-72) · transcript line 2664.


```bash
packer version
aws sts get-caller-identity
```


[Chat command 73](docs/command-history.md#command-73) · transcript line 2702.


```bash
curl "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb" \
  -o session-manager-plugin.deb

sudo dpkg -i session-manager-plugin.deb
session-manager-plugin --version
```

## 3. Authenticate GitHub and clone the repository

I used HTTPS with GitHub CLI for the repository. When browser authentication timed out, I checked connectivity before retrying authentication. I selected repository access for the private repository at that stage; visibility was changed later. I did not put a token in a Git command or commit it.


[Chat command 98](docs/command-history.md#command-98) · transcript line 3122.


```bash
gh auth login
```


[Chat command 101](docs/command-history.md#command-101) · transcript line 3193.


```bash
curl -I --connect-timeout 10 https://api.github.com/
curl -I --connect-timeout 10 https://github.com/
```


[Chat command 105](docs/command-history.md#command-105) · transcript line 3236.


```bash
gh auth status
```


[Chat command 109](docs/command-history.md#command-109) · transcript line 3293.


```bash
mkdir -p ~/Downloads
mv ~/projects/project-3-secure-cicd-pipeline/session-manager-plugin.deb ~/Downloads/

cd ~/projects
git clone https://github.com/DelaneKay/project-3-secure-cicd-pipeline.git
```


[Chat command 110](docs/command-history.md#command-110) · transcript line 3303.


```bash
cd ~/projects/project-3-secure-cicd-pipeline
git status --short --branch
```

The original folder contained the downloaded Session Manager package and was not a Git repository. The move-and-clone commands above belong to that initial recovery, not every future checkout. I used `git status --short --branch` to confirm that `master` tracked `origin/master`.

## 4. Create the temporary builder role and instance profile

I created the EC2 role used by temporary Packer builders to register with Systems Manager. This role is separate from my Packer operator role and from the runtime roles used by the application, SonarQube and scanner. I ran the creation once; if a later command failed, I inspected the resources rather than blindly recreating them.


[Chat command 85](docs/command-history.md#command-85) · transcript line 2860.


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


[Chat command 93](docs/command-history.md#command-93) · transcript line 2998.


```bash
aws iam list-attached-role-policies \
  --role-name project-3-packer-builder-role \
  --profile mds-devsecops-lab \
  --output table
```

## 5. Give Packer its own assumed role

The first build could not find usable credentials even though AWS CLI could identify my user. I created an operator role, granted my IAM user permission to assume it, and configured a login-backed credential process. Packer then used the `project-3-packer` role profile. The policy below is the actual lab bootstrap policy; its regional wildcard permissions are a lab limitation, not a claim of production-grade least privilege.


[Chat command 183](docs/command-history.md#command-183) · transcript line 4888.


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


[Chat command 188](docs/command-history.md#command-188) · transcript line 5270.


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


[Chat command 190](docs/command-history.md#command-190) · transcript line 5405.


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

I chose Ubuntu 24.04 LTS amd64 and retrieved Canonical's public AMI parameter. The recorded image was `ami-REPLACE_WITH_YOUR_ID`, owned by Canonical account `099720109477`. Before building, I inspected the default VPC, subnet public-IP behavior and route to the internet gateway.


[Chat command 116](docs/command-history.md#command-116) · transcript line 3514.


```bash
aws ssm get-parameter \
  --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
  --query 'Parameter.Value' \
  --output text \
  --profile mds-devsecops-lab \
  --region us-east-1
```


[Chat command 118](docs/command-history.md#command-118) · transcript line 3572.


```bash
aws ec2 describe-images \
  --image-ids ami-REPLACE_WITH_YOUR_ID \
  --query 'Images[0].[Name,Architecture,OwnerId,State]' \
  --output table \
  --profile mds-devsecops-lab \
  --region us-east-1
```


[Chat command 94](docs/command-history.md#command-94) · transcript line 3027.


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


[Chat command 95](docs/command-history.md#command-95) · transcript line 3058.


```bash
aws ec2 describe-route-tables \
  --region us-east-1 \
  --profile mds-devsecops-lab \
  --filters Name=vpc-id,Values=vpc-REPLACE_WITH_YOUR_ID \
  --query 'RouteTables[].{RouteTable:RouteTableId,Main:Associations[?Main==`true`]|[0].Main,Subnets:Associations[].SubnetId,Routes:Routes[].{Destination:DestinationCidrBlock,Gateway:GatewayId,State:State}}' \
  --output json
```

## 7. Create a no-ingress Packer security group

I stopped using the default security group for builds and created a dedicated group with no inbound rules. Its outbound rules allowed TCP 80 for package mirrors and TCP 443 for SSM and downloads. Packer used its SSH communicator inside an SSM tunnel; this lab did not open public port 22. The temporary communicator is still SSH internally, so I do not describe it as an SSH-free Packer protocol.


[Chat command 132](docs/command-history.md#command-132) · transcript line 4308.


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

I created the Juice Shop template and installation script, then formatted, initialized and validated the template before building. The original file-writing commands, including the full script and its UFW changes, are in the command history. For a fresh reproduction I use the corrected checked-out script: the early `snap enable` command was fixed to `snap start` before the successful build.


[Chat command 119](docs/command-history.md#command-119) · transcript line 3592.


```bash
cd ~/projects/project-3-secure-cicd-pipeline
mkdir -p packer/juice-shop/scripts
```


[Chat command 125](docs/command-history.md#command-125) · transcript line 3811.


```bash
packer init packer/juice-shop
```


[Chat command 135](docs/command-history.md#command-135) · transcript line 4412.


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


[Chat command 195](docs/command-history.md#command-195) · transcript line 5514.


```bash
sed -i 's/^[[:space:]]*snap enable amazon-ssm-agent$/  snap start amazon-ssm-agent/' \
  packer/juice-shop/scripts/install-juice-shop.sh

sed -n '100,112p' packer/juice-shop/scripts/install-juice-shop.sh
```


[Chat command 192](docs/command-history.md#command-192) · transcript line 5452.


```bash
cd ~/projects/project-3-secure-cicd-pipeline

AWS_PROFILE=project-3-packer AWS_REGION=us-east-1 packer build \
  -var 'source_ami_id=ami-REPLACE_WITH_YOUR_ID' \
  -var 'subnet_id=subnet-REPLACE_WITH_YOUR_ID' \
  -var 'security_group_id=sg-REPLACE_WITH_YOUR_ID' \
  packer/juice-shop
```

The first successful Juice Shop image was `ami-REPLACE_WITH_YOUR_ID`. I baked Node.js, Juice Shop 20.3.0, its systemd service, SSM support, CloudWatch configuration and host firewall into the image. [Original template](docs/command-history.md#command-124), [full UFW script](docs/command-history.md#command-129), and the later file corrections in the configuration history explain what the build installed. I did not run that provisioning script against the deployed application server.

## 9. Create the SonarQube image and validate all required inputs

I created a separate SonarQube template, installer and CloudWatch installer. I loaded `version.env` because a valid template still needs values for source AMI, subnet, security group, SonarQube version and Java package. Running validation without those values produced the unset-variable errors we saw.


[Chat command 213](docs/command-history.md#command-213) · transcript line 5781.


```bash
cd ~/projects/project-3-secure-cicd-pipeline

cat > packer/sonarqube/version.env <<'EOF'
SONARQUBE_VERSION=26.10.0.133078
JAVA_PACKAGE=openjdk-21-jdk
EOF
```


[Chat command 214](docs/command-history.md#command-214) · transcript line 5798.


```bash
nano packer/sonarqube/scripts/install-sonarqube.sh
```


[Chat command 220](docs/command-history.md#command-220) · transcript line 6053.


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


[Chat command 223](docs/command-history.md#command-223) · transcript line 6198.


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


[Chat command 224](docs/command-history.md#command-224) · transcript line 6233.


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


[Chat command 226](docs/command-history.md#command-226) · transcript line 6357.


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


[Chat command 228](docs/command-history.md#command-228) · transcript line 6418.


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

I built a third AMI for the AWS scanner runner. I pinned the runner, Gitleaks, SonarScanner, Dependency-Check, ZAP, Terraform, AWS CLI and Java versions. The complete initial installer appears in the history; subsequent fixes added Node.js/npm and tested tool execution as `actions-runner`. I did not install Gitleaks in WSL to satisfy a workflow intended to run in AWS.


[Chat command 234](docs/command-history.md#command-234) · transcript line 6517.


```bash
cd ~/projects/project-3-secure-cicd-pipeline
mkdir -p packer/github-runner/scripts
```


[Chat command 235](docs/command-history.md#command-235) · transcript line 6566.


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


[Chat command 237](docs/command-history.md#command-237) · transcript line 6602.


```bash
nano packer/github-runner/scripts/install-runner.sh
```


[Chat command 250](docs/command-history.md#command-250) · transcript line 7546.


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


[Chat command 251](docs/command-history.md#command-251) · transcript line 7690.


```bash
packer init packer/github-runner
```


[Chat command 252](docs/command-history.md#command-252) · transcript line 7700.


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


[Chat command 258](docs/command-history.md#command-258) · transcript line 8142.


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

The full initial installer is [command 255](docs/command-history.md#command-255). The final recorded installer and Packer template are in [the configuration record](docs/configuration-record.md). A runner AMI contains software, not a permanent GitHub registration token.

## 11. Commit the image build files

I checked the Packer files before staging them. My first commit failed because Git had no author name; I set the repository's author from my authenticated GitHub account, committed again and pushed. A later 403 on push required fixing GitHub write permission, rather than changing AWS access.


[Chat command 260](docs/command-history.md#command-260) · transcript line 8200.


```bash
git status --short
```


[Chat command 261](docs/command-history.md#command-261) · transcript line 8211.


```bash
find packer -maxdepth 4 -type f -print | sort
```


[Chat command 262](docs/command-history.md#command-262) · transcript line 8224.


```bash
git add packer
git diff --cached --stat
git status --short
```


[Chat command 265](docs/command-history.md#command-265) · transcript line 8258.


```bash
gh_user="$(gh api user --jq .login)"
gh_user_id="$(gh api user --jq .id)"
git config user.name "$gh_user"
git config user.email "${gh_user_id}+${gh_user}@users.noreply.github.com"

git commit -m "Add hardened Packer AMI builds for Lab 3"
```


[Chat command 263](docs/command-history.md#command-263) · transcript line 8239.


```bash
git commit -m "Add hardened Packer AMI builds for Lab 3"
```


[Chat command 266](docs/command-history.md#command-266) · transcript line 8278.


```bash
gh auth status --hostname github.com
```


[Chat command 268](docs/command-history.md#command-268) · transcript line 8298.


```bash
git push origin master
```


[Chat command 269](docs/command-history.md#command-269) · transcript line 8306.


```bash
git status --short --branch
```

## 12. Split Terraform into independent roots

I created five separate root directories rather than one long Terraform file. Network owns the VPC, subnets, routes and security groups; database owns RDS; observability owns log groups and SNS; compute owns Juice Shop and the runner; sonarqube owns the SonarQube instance. At this point only network and database contained files—empty directories were not missing Git commits.


[Chat command 272](docs/command-history.md#command-272) · transcript line 8361.


```bash
mkdir -p terraform/network terraform/database terraform/compute terraform/sonarqube terraform/observability
```


[Chat command 281](docs/command-history.md#command-281) · transcript line 8501.


```bash
nano terraform/.gitignore
```


[Chat command 282](docs/command-history.md#command-282) · transcript line 8509.


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


[Chat command 384](docs/command-history.md#command-384) · transcript line 12028.


```bash
cd ~/projects/project-3-secure-cicd-pipeline

find terraform -maxdepth 3 -type f \
  ! -path '*/.terraform/*' \
  ! -name 'terraform.tfstate*' \
  ! -name '*.tfplan' \
  -print | sort
```


[Chat command 393](docs/command-history.md#command-393) · transcript line 12158.


```bash
cd ~/projects/project-3-secure-cicd-pipeline
find terraform/compute terraform/sonarqube terraform/observability \
  -maxdepth 2 -type f -print 2>/dev/null | sort
```

The initial network file creation is preserved at [commands 273–322](docs/command-history.md#command-273), and database creation at [commands 326–340](docs/command-history.md#command-326). The later compute/observability/SonarQube files were created through the repository integration and are represented in the configuration record and repository. Separate roots mean separate state and explicit execution order, not that Terraform automatically runs every directory.

## 13. Validate and test the original network layer manually

During the initial build I ran Terraform locally to test the network root. I used two public and two private subnets in `10.20.0.0/16` and selected interface VPC endpoints. The plan initially showed 14 resources, then 21 after the remaining security groups were added. This manual stage is part of the history; it is not the final routine deployment method.


[Chat command 283](docs/command-history.md#command-283) · transcript line 8527.


```bash
terraform -chdir=terraform/network init
```


[Chat command 284](docs/command-history.md#command-284) · transcript line 8540.


```bash
terraform -chdir=terraform/network validate
```


[Chat command 294](docs/command-history.md#command-294) · transcript line 8789.


```bash
cd ~/projects/project-3-secure-cicd-pipeline
terraform -chdir=terraform/network fmt
terraform -chdir=terraform/network validate
```


[Chat command 304](docs/command-history.md#command-304) · transcript line 9058.


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


[Chat command 306](docs/command-history.md#command-306) · transcript line 9105.


```bash
cd ~/projects/project-3-secure-cicd-pipeline
terraform -chdir=terraform/network apply
```


[Chat command 312](docs/command-history.md#command-312) · transcript line 9188.


```bash
cd ~/projects/project-3-secure-cicd-pipeline
terraform -chdir=terraform/network apply
```


[Chat command 323](docs/command-history.md#command-323) · transcript line 9593.


```bash
cd ~/projects/project-3-secure-cicd-pipeline
terraform -chdir=terraform/network fmt
terraform -chdir=terraform/network validate
```


[Chat command 325](docs/command-history.md#command-325) · transcript line 9616.


```bash
cd ~/projects/project-3-secure-cicd-pipeline
terraform -chdir=terraform/network apply
```

## 14. Create and test the original SonarQube database layer

I checked orderable PostgreSQL 17 versions, wrote the RDS and subnet-group files, and validated the database root before its original manual apply. RDS is a managed service, so it was created by Terraform, not baked by Packer. The recorded class was `db.t4g.micro`; the database was encrypted and private.


[Chat command 334](docs/command-history.md#command-334) · transcript line 9782.


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


[Chat command 335](docs/command-history.md#command-335) · transcript line 9817.


```bash
cd ~/projects/project-3-secure-cicd-pipeline
nano terraform/database/terraform.tfvars
```


[Chat command 336](docs/command-history.md#command-336) · transcript line 9824.


```hcl
db_engine_version = "17.11"
db_instance_class = "db.t4g.micro"
```


[Chat command 337](docs/command-history.md#command-337) · transcript line 9835.


```bash
cd ~/projects/project-3-secure-cicd-pipeline
nano terraform/database/database.tf
```


[Chat command 338](docs/command-history.md#command-338) · transcript line 9842.


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


[Chat command 339](docs/command-history.md#command-339) · transcript line 9891.


```bash
cd ~/projects/project-3-secure-cicd-pipeline
nano terraform/database/outputs.tf
```


[Chat command 340](docs/command-history.md#command-340) · transcript line 9898.


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


[Chat command 341](docs/command-history.md#command-341) · transcript line 9931.


```bash
cd ~/projects/project-3-secure-cicd-pipeline
terraform -chdir=terraform/database fmt
terraform -chdir=terraform/database init
terraform -chdir=terraform/database validate
```


[Chat command 343](docs/command-history.md#command-343) · transcript line 9955.


```bash
cd ~/projects/project-3-secure-cicd-pipeline
terraform -chdir=terraform/database apply
```

My original state reference was local. I later changed both roots to S3-backed state for GitHub execution. I did not treat an existing AWS database as automatically managed just because another backend was empty; that caused the import challenge recorded below.

## 15. Move routine Terraform execution into GitHub Actions

I kept the five roots but put the repeated init/plan/apply logic in `terraform-layer.yml`. The deployment workflow calls it in dependency order. GitHub-hosted runners were explicitly allowed for Terraform; security scanners stayed on the AWS runner. I committed the roots and workflows so a runner could actually check out the same code I had tested.


[Chat command 487](docs/command-history.md#command-487) · transcript line 14276.


```bash
git add -A
git diff --cached --check
git diff --cached --stat
git diff --cached --name-only
```


[Chat command 505](docs/command-history.md#command-505) · transcript line 14999.


```bash
git add -A
git status --short
```


[Chat command 506](docs/command-history.md#command-506) · transcript line 15062.


```bash
git diff --cached --check && git commit -m "Add Terraform CI and AWS Gitleaks workflow"
```


[Chat command 507](docs/command-history.md#command-507) · transcript line 15075.


```bash
git push origin master
```

The original Gitleaks move to AWS is preserved in [command 502](docs/command-history.md#command-502). I retained format/validation and Checkov in Terraform validation. Pull requests validate without AWS deployment credentials; trusted post-merge/manual deployment uses OIDC. The complete combined-era deployment and scan workflows are in the configuration record.

## 16. Bootstrap the private remote-state bucket

Before GitHub could initialize an S3 backend, I created the state bucket with the repository bootstrap script. This was a one-time AWS CLI bootstrap, not a Terraform root. The script enables versioning and encryption, blocks public access and rejects insecure transport. Each root uses `project-3/<root>/terraform.tfstate` with native `.tflock` locking.


[Chat command 455](docs/command-history.md#command-455) · transcript line 13062.


```bash
cd ~/projects/project-3-secure-cicd-pipeline

aws sts get-caller-identity --profile mds-devsecops-lab
```


[Chat command 456](docs/command-history.md#command-456) · transcript line 13070.


```bash
AWS_PROFILE=mds-devsecops-lab AWS_REGION=us-east-1 \
  ./scripts/bootstrap-terraform-state.sh
```


[Chat command 457](docs/command-history.md#command-457) · transcript line 13077.


```bash
aws s3api head-bucket \
  --bucket project-3-tfstate-YOUR_ACCOUNT_ID-us-east-1 \
  --expected-bucket-owner YOUR_ACCOUNT_ID \
  --profile mds-devsecops-lab \
  --region us-east-1
```

## 17. Create the OIDC provider and Terraform roles

I created the GitHub OIDC provider and separate plan/apply roles, validated their permission documents with Access Analyzer, and attached the policies. Access Analyzer returned `[]` in that check; that meant it found no reported policy issues, not that every future AWS operation had been proven to work.


[Chat command 458](docs/command-history.md#command-458) · transcript line 13107.


```bash
aws iam list-open-id-connect-providers \
  --profile mds-devsecops-lab \
  --query 'OpenIDConnectProviderList[].Arn' \
  --output table
```


[Chat command 459](docs/command-history.md#command-459) · transcript line 13131.


```bash
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --profile mds-devsecops-lab \
  --no-cli-pager
```


[Chat command 460](docs/command-history.md#command-460) · transcript line 13147.


```bash
aws iam get-open-id-connect-provider \
  --open-id-connect-provider-arn arn:aws:iam::YOUR_ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com \
  --profile mds-devsecops-lab \
  --query '{Url:Url,ClientIDList:ClientIDList}' \
  --output json
```


[Chat command 462](docs/command-history.md#command-462) · transcript line 13190.


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


[Chat command 463](docs/command-history.md#command-463) · transcript line 13311.


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


[Chat command 464](docs/command-history.md#command-464) · transcript line 13340.


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


[Chat command 465](docs/command-history.md#command-465) · transcript line 13378.


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

In GitHub Settings → Environments, I created `terraform-lab-apply`, restricted deployment to `master`, added `DelaneKay` as required reviewer, left Prevent self-review unchecked for this solo lab, disabled administrator bypass and saved. I reviewed each readable Terraform plan before approving its saved-plan apply. These were browser actions, so I do not invent a terminal command that claims to have performed them.


[Chat command 465](docs/command-history.md#command-465) · transcript line 13378.


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

I also created a GitHub App, selected only this repository, granted repository Administration write, generated its PEM key and installed it. I stored `RUNNER_GITHUB_APP_ID` and `RUNNER_GITHUB_APP_PRIVATE_KEY` as Actions secrets, never in Git. The workflow creates a short-lived registration token, places it in SSM SecureString, and the new runner consumes it at first boot. The exact implementation is in [terraform-layer.yml](.github/workflows/terraform-layer.yml); I inspect the workflow rather than manually placing a registration token in Terraform state.

## 19. Run the standalone Terraform deployment and verify AWS resources

I first ran `Terraform deployment` on `master`, approved the layer plans and checked the resulting EC2 and RDS resources. Networking applied first, then database and observability could progress independently; compute and SonarQube waited for their required upstream state. A first deployment needs this ordering because outputs do not exist before the upstream apply.


[Chat command 921](docs/command-history.md#command-921) · transcript line 21922.


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


[Chat command 922](docs/command-history.md#command-922) · transcript line 21959.


```bash
aws ssm describe-instance-information \
  --profile mds-devsecops-lab \
  --region us-east-1 \
  --query 'InstanceInformationList[].{InstanceId:InstanceId,PingStatus:PingStatus,Platform:PlatformName}' \
  --output table
```

In GitHub I used Actions → Terraform deployment → Run workflow → master. The later combined pipeline reuses this deployment workflow. A green Terraform job proves resource operations succeeded; I still checked the application and SonarQube health separately.

## 20. Preserve immutability when a service fails

SonarQube repeatedly failed to listen on port 9000 even when systemd reported activating. I used SSM for read-only diagnostics, fixed the Packer source, rebuilt an AMI and let Terraform replace the instance. I did not turn a successful diagnosis into a permanent patch on the deployed server. These permission commands belong inside the image build, followed by the non-root execution test.


[Chat command 1842](docs/command-history.md#command-1842) · transcript line 35434.


```bash
chown -R root:root /usr/local/aws-cli
chmod -R a+rX,u+w,go-w /usr/local/aws-cli
```


[Chat command 1843](docs/command-history.md#command-1843) · transcript line 35443.


```bash
runuser -u sonarqube -- /bin/bash -c \
  'test -x /usr/local/aws-cli/v2/current/bin/aws &&
   /usr/local/aws-cli/v2/current/bin/aws --version'
```


[Chat command 2015](docs/command-history.md#command-2015) · transcript line 38156.


```bash
cd ~/projects/project-3-secure-cicd-pipeline

git switch master
git pull --ff-only

aws sts get-caller-identity \
  --profile project-3-packer \
  --query Arn \
  --output text
```


[Chat command 1841](docs/command-history.md#command-1841) · transcript line 35413.


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

I encountered the same AWS CLI permission problem on the scanner runner, then discovered Node.js/npm were absent. I corrected the runner image, rebuilt it, recorded its AMI and backing snapshot, and replaced the EC2 runner through Terraform. The new runner used `ami-REPLACE_WITH_YOUR_ID`; the old offline GitHub runner entries were historical registrations, not usable capacity.


[Chat command 2060](docs/command-history.md#command-2060) · transcript line 38848.


```bash
cd ~/projects/project-3-secure-cicd-pipeline

git switch master
git pull --ff-only
```


[Chat command 2061](docs/command-history.md#command-2061) · transcript line 38857.


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


[Chat command 2062](docs/command-history.md#command-2062) · transcript line 38888.


```bash
aws ec2 describe-images \
  --profile mds-devsecops-lab \
  --region us-east-1 \
  --image-ids ami-REPLACE_WITH_YOUR_ID \
  --query 'Images[].{AMI:ImageId,State:State,Snapshot:BlockDeviceMappings[0].Ebs.SnapshotId}' \
  --output table
```


[Chat command 2063](docs/command-history.md#command-2063) · transcript line 38906.


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


[Chat command 2064](docs/command-history.md#command-2064) · transcript line 38925.


```bash
gh pr create \
  --base master \
  --head feat/runner-node-npm-ami \
  --title "Record runner AMI with Node.js and npm" \
  --body "Record the rebuilt scanner runner AMI and its backing snapshot."
```


[Chat command 2066](docs/command-history.md#command-2066) · transcript line 38970.


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


[Chat command 1962](docs/command-history.md#command-1962) · transcript line 37385.


```bash
gh api repos/DelaneKay/project-3-secure-cicd-pipeline/actions/runners \
  --jq '.runners[] | {name, status, busy}'
```


[Chat command 2067](docs/command-history.md#command-2067) · transcript line 38992.


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


[Chat command 2068](docs/command-history.md#command-2068) · transcript line 39009.


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

I ran Gitleaks on the self-hosted scanner after it registered online. I scanned full Git history and uploaded a redacted JSON report. The first finding was the public AWS CLI signing-key fingerprint; I examined the exact historical commit before adding a single-finding ignore entry. I did not disable the generic API-key rule globally.


[Chat command 1856](docs/command-history.md#command-1856) · transcript line 35731.


```bash
gh workflow run gitleaks-aws.yml --ref master

gh run list --workflow gitleaks-aws.yml --limit 3
```


[Chat command 1857](docs/command-history.md#command-1857) · transcript line 35746.


```bash
gh run watch 41624217203 --exit-status
```


[Chat command 1858](docs/command-history.md#command-1858) · transcript line 35752.


```bash
gh run view 41624217203
```


[Chat command 1859](docs/command-history.md#command-1859) · transcript line 35783.


```bash
git show 9d2406ca349dfe9ad1aac51dedc80129a819c226:packer/sonarqube/scripts/install-sonarqube.sh \
  | sed -n '9p' \
  | cut -d= -f1
```


[Chat command 1860](docs/command-history.md#command-1860) · transcript line 35800.


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


[Chat command 1861](docs/command-history.md#command-1861) · transcript line 35819.


```bash
git add .gitleaksignore
git diff --cached --check
git commit -m "Exclude verified public AWS CLI signing fingerprint"
git push -u origin fix/gitleaks-public-key-fingerprint
```


[Chat command 1862](docs/command-history.md#command-1862) · transcript line 35828.


```bash
gh pr create \
  --base master \
  --head fix/gitleaks-public-key-fingerprint \
  --title "Exclude public AWS CLI signing fingerprint from Gitleaks" \
  --body "Document and suppress one verified false positive using its exact commit, file, rule, and line. The value is the public AWS CLI signing-key fingerprint used for package verification."
```


[Chat command 1863](docs/command-history.md#command-1863) · transcript line 35838.


```bash
gh workflow run gitleaks-aws.yml --ref master
gh run list --workflow gitleaks-aws.yml --limit 3
```


[Chat command 1864](docs/command-history.md#command-1864) · transcript line 35852.


```bash
gh run watch 41626050135 --exit-status

gh run download 41626050135 \
  --dir reports/gitleaks-41626050135

find reports/gitleaks-41626050135 -name 'gitleaks.json' -exec cat {} \;
```

The verified rerun returned `[]`. Vulnerability findings remain report-only, while a missing executable or missing report is a scanner failure. The current complete workflow is preserved in the configuration record; the initial complete workflow is command 502 in the command history.

## 23. Open SonarQube through SSM and bootstrap its project

I forwarded port 9000 to localhost with SSM, logged in to SonarQube and changed its initial password. I created the protected `sonarqube-admin` GitHub environment with `SONAR_HOST_URL` and `SONAR_ADMIN_TOKEN`, then ran the project setup workflow on the AWS runner. The setup script creates/reconciles the private `project-3-juice-shop` project and discovers the built-in language defaults.


[Chat command 1890](docs/command-history.md#command-1890) · transcript line 36167.


```bash
aws ssm start-session \
  --profile mds-devsecops-lab \
  --region us-east-1 \
  --target i-REPLACE_WITH_YOUR_ID \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["9000"],"localPortNumber":["9000"]}'
```


[Chat command 1891](docs/command-history.md#command-1891) · transcript line 36239.


```bash
cd ~/projects/project-3-secure-cicd-pipeline

gh workflow run sonarqube-setup.yml --ref master
gh run list --workflow sonarqube-setup.yml --limit 3
```

I used `http://localhost:9000/projects` in my browser. A version-specific profile-name mismatch initially failed setup: this release offered `Sonar way core`, `extended` and `comprehensive`, not a single profile literally named `Sonar way`. The corrected setup selected the language's built-in default. The next setup run succeeded without a host change or AMI rebuild.

## 24. Separate SonarQube analysis and reporting permissions

I created `sonarqube-scan`, set `SONAR_HOST_URL` to the reachable private SonarQube URL, and stored the project analysis token as `SONAR_TOKEN`. I created `project-3-reporter`, granted Browse only at `http://localhost:9000/project_roles?id=project-3-juice-shop`, and stored that account's user token as `SONAR_REPORT_TOKEN`. A token inherits its owner's permissions; I did not use the administrator token for routine reporting.


[Chat command 1963](docs/command-history.md#command-1963) · transcript line 37402.


```bash
gh workflow run sonarqube-analysis.yml --ref master

gh run list --workflow sonarqube-analysis.yml --limit 3
```


[Chat command 1964](docs/command-history.md#command-1964) · transcript line 37417.


```bash
gh run watch 41648646890 --exit-status
```


[Chat command 1965](docs/command-history.md#command-1965) · transcript line 37423.


```bash
gh run view 41648646890
```


[Chat command 1966](docs/command-history.md#command-1966) · transcript line 37429.


```bash
gh run view 41648646890 --log-failed
```

The workflow checked out Juice Shop v20.3.0, submitted analysis and kept quality-gate findings report-only. The later export step waited for processing and saved issue summaries and the analysis receipt. A screenshot once displayed a token; reusable documentation must not preserve token values. Account/token creation was performed in the UI, not by an invented shell command.

## 25. Export SonarQube results and verify CloudWatch/SNS

I added the reporting step only after the standalone analysis worked. I downloaded the report to inspect its summary and verified a CloudWatch stream. SNS initially had no subscriptions, so successful publish calls could not produce an email. I supplied `TF_NOTIFICATION_EMAIL` through the repository variable, applied observability through the workflow, confirmed AWS's subscription email, and reran analysis.


[Chat command 2022](docs/command-history.md#command-2022) · transcript line 38299.


```bash
gh workflow run sonarqube-analysis.yml --ref master

gh run list --workflow sonarqube-analysis.yml --limit 3
```


[Chat command 2023](docs/command-history.md#command-2023) · transcript line 38314.


```bash
gh run watch 41671030481 --exit-status
```


[Chat command 2024](docs/command-history.md#command-2024) · transcript line 38320.


```bash
gh run view 41671030481 --log-failed
```


[Chat command 2025](docs/command-history.md#command-2025) · transcript line 38335.


```bash
gh run download 41671030481 \
  --name sonarqube-results \
  --dir reports/sonarqube-41671030481

cat reports/sonarqube-41671030481/summary.json
```


[Chat command 2026](docs/command-history.md#command-2026) · transcript line 38354.


```bash
aws sns list-subscriptions-by-topic \
  --profile mds-devsecops-lab \
  --region us-east-1 \
  --topic-arn arn:aws:sns:us-east-1:YOUR_ACCOUNT_ID:project-3-secure-cicd-pipeline-scan-findings \
  --query 'Subscriptions[].{Protocol:Protocol,Status:SubscriptionArn}' \
  --output table
```


[Chat command 2027](docs/command-history.md#command-2027) · transcript line 38363.


```bash
aws logs describe-log-streams \
  --profile mds-devsecops-lab \
  --region us-east-1 \
  --log-group-name /project-3/pipeline/scans \
  --log-stream-name-prefix sonarqube-41671030481 \
  --query 'logStreams[].{Stream:logStreamName,LastEvent:lastEventTimestamp}' \
  --output table
```


[Chat command 2030](docs/command-history.md#command-2030) · transcript line 38407.


```bash
cd ~/projects/project-3-secure-cicd-pipeline

grep -n -i 'notification_email' \
  terraform/observability/variables.tf \
  .github/workflows/terraform-layer.yml \
  .github/workflows/terraform-deploy.yml
```


[Chat command 2031](docs/command-history.md#command-2031) · transcript line 38451.


```bash
aws sns list-subscriptions-by-topic \
  --profile mds-devsecops-lab \
  --region us-east-1 \
  --topic-arn arn:aws:sns:us-east-1:YOUR_ACCOUNT_ID:project-3-secure-cicd-pipeline-scan-findings \
  --output json --no-cli-pager
```


[Chat command 2032](docs/command-history.md#command-2032) · transcript line 38472.


```bash
gh workflow run sonarqube-analysis.yml --ref master

gh run list --workflow sonarqube-analysis.yml --limit 3
```


[Chat command 2033](docs/command-history.md#command-2033) · transcript line 38487.


```bash
gh run watch 41695305784 --exit-status
```

The summary contained 272 SonarQube issues: 104 blocker, 10 critical, 96 major and 62 minor. These are SonarQube issue severities, not proof of 272 exploitable vulnerabilities. The quality status was `OK`. CloudWatch receives one aggregate event and SNS one concise summary per scan attempt, while full findings stay in report artifacts.

## 26. Run Dependency-Check separately

I verified Node.js, npm and Dependency-Check as the runner account before starting SCA. I created the `dependency-check` GitHub environment and stored `NVD_API_KEY` there. The initial source-tree workflow expected a top-level lockfile that was absent from the selected release; I changed it to verify and scan the packaged Juice Shop release with its installed dependencies.


[Chat command 2067](docs/command-history.md#command-2067) · transcript line 38992.


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


[Chat command 2068](docs/command-history.md#command-2068) · transcript line 39009.


```bash
aws ssm get-command-invocation \
  --profile mds-devsecops-lab \
  --region us-east-1 \
  --command-id 5bd01d7f-c80e-4a73-9f11-e34c94f1a077 \
  --instance-id i-REPLACE_WITH_YOUR_ID \
  --query '{Status:Status,Output:StandardOutputContent,Errors:StandardErrorContent}' \
  --output json
```


[Chat command 2134](docs/command-history.md#command-2134) · transcript line 39918.


```bash
gh run list --workflow dependency-check.yml --limit 3
```


[Chat command 2135](docs/command-history.md#command-2135) · transcript line 39933.


```bash
gh run view 41719010612 --log-failed
```


[Chat command 2136](docs/command-history.md#command-2136) · transcript line 39964.


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

The missing NVD key failed updates with exit 13. A later run wrote reports but still ended with unexpected exceptions and exit 14; that was not a clean scan. I inspected the report and added sanitized exception diagnostics. The confirmed parser correction changed the empty CPE skip-list property to an explicit empty JSON array.


[Chat command 2174](docs/command-history.md#command-2174) · transcript line 40502.


```text
ecosystem.skip.cpeanalyzer=
```


[Chat command 2175](docs/command-history.md#command-2175) · transcript line 40510.


```properties
ecosystem.skip.cpeanalyzer=[]
```


[Chat command 2136](docs/command-history.md#command-2136) · transcript line 39964.


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

The final recorded summary reported 16,284 dependencies, 20 vulnerable dependencies and 66 vulnerability occurrences: critical 23, high 13, medium 24 and low 6. Counts can change as vulnerability data changes. The full corrected command, NVD key handling and diagnostic handling are preserved in the Dependency-Check workflow in the configuration record.

## 28. Verify ZAP and target reachability before DAST

I checked the installed ZAP launcher and automation add-on as `actions-runner`. My first attempt used a nonexistent user called `runner`; that was an account-name mistake, not a reason to create a new user on the deployed host. I then checked the running Juice Shop instance and HTTP reachability from the scanner.


[Chat command 2206](docs/command-history.md#command-2206) · transcript line 40893.


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


[Chat command 2207](docs/command-history.md#command-2207) · transcript line 40910.


```bash
aws ssm get-command-invocation \
  --profile mds-devsecops-lab \
  --region us-east-1 \
  --command-id d24cf239-195f-40ad-bd05-7a9b6037e34d \
  --instance-id i-REPLACE_WITH_YOUR_ID \
  --query '{Status:Status,Output:StandardOutputContent,Errors:StandardErrorContent}' \
  --output json
```


[Chat command 2213](docs/command-history.md#command-2213) · transcript line 41001.


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


[Chat command 2214](docs/command-history.md#command-2214) · transcript line 41018.


```bash
aws ssm get-command-invocation \
  --profile mds-devsecops-lab \
  --region us-east-1 \
  --command-id 1e86f2b0-ec76-42d0-a894-99d8a2e534b0 \
  --instance-id i-REPLACE_WITH_YOUR_ID \
  --query '{Status:Status,Output:StandardOutputContent,Errors:StandardErrorContent}' \
  --output json
```


[Chat command 2216](docs/command-history.md#command-2216) · transcript line 41055.


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


[Chat command 2217](docs/command-history.md#command-2217) · transcript line 41077.


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


[Chat command 2218](docs/command-history.md#command-2218) · transcript line 41094.


```bash
aws ssm get-command-invocation \
  --profile mds-devsecops-lab \
  --region us-east-1 \
  --command-id ef818084-33c1-4bd4-940a-8fc3bcb6a4ed \
  --instance-id i-REPLACE_WITH_YOUR_ID \
  --query '{Status:Status,Output:StandardOutputContent,Errors:StandardErrorContent}' \
  --output json
```


[Chat command 2231](docs/command-history.md#command-2231) · transcript line 41234.


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


[Chat command 2232](docs/command-history.md#command-2232) · transcript line 41251.


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

I used Actions → Juice Shop ZAP DAST → Run workflow → master after merging its workflow. ZAP discovers exactly one running Project-tagged Juice Shop instance, checks the address is inside `10.20.0.0/16`, tests HTTP reachability, then runs a bounded unauthenticated spider and active scan. I limited the target to my lab application. The full command and automation plan are reproduced in the configuration record.

The successful run was `41832567685`, with five alert types: two medium and three informational. It produced JSON/HTML reports and an SNS email. This is limited unauthenticated coverage: it does not claim to exercise all Juice Shop routes, JavaScript flows or authenticated features.

```bash
gh run view 41832567685
```

This uses the same `gh run view` command used throughout the lab, with the successful ZAP run ID shown in the recorded notification.

## 30. Combine the tested workflows without deleting the separate ones

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


[Chat command 2402](docs/command-history.md#command-2402) · transcript line 43545.


```bash
mkdir -p ~/project-3-artifact-review

gh run download 41846334576 \
  --repo DelaneKay/project-3-secure-cicd-pipeline \
  --dir ~/project-3-artifact-review

find ~/project-3-artifact-review -type f | sort
```

The successful run is [available in Actions](https://github.com/DelaneKay/project-3-secure-cicd-pipeline/actions/runs/41846334576). I kept reviewed scanner evidence for the portfolio and did not publish binary Terraform plans/state as portfolio examples. Reports demonstrate what a particular run actually found; source code alone cannot prove the tools executed or the notification arrived.

## 32. Check the trust boundaries against the actual configuration

I checked the boundaries using the same identity, network, runner-registration and subscription queries I used during the build. Each boundary below identifies who may cross it and which control makes that possible.


[Chat command 69](docs/command-history.md#command-69) · transcript line 2612.


```bash
export AWS_PROFILE=mds-devsecops-lab
export AWS_REGION=us-east-1
export AWS_DEFAULT_REGION=us-east-1

aws sts get-caller-identity
packer version
```


[Chat command 1428](docs/command-history.md#command-1428) · transcript line 30063.


```bash
aws ec2 describe-vpcs \
  --profile mds-devsecops-lab \
  --region us-east-1 \
  --filters "Name=tag:Project,Values=project-3-secure-cicd-pipeline" \
  --query 'Vpcs[].{VpcId:VpcId,Cidr:CidrBlock}' \
  --output table
```


[Chat command 1429](docs/command-history.md#command-1429) · transcript line 30081.


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


[Chat command 1962](docs/command-history.md#command-1962) · transcript line 37385.


```bash
gh api repos/DelaneKay/project-3-secure-cicd-pipeline/actions/runners \
  --jq '.runners[] | {name, status, busy}'
```


[Chat command 2031](docs/command-history.md#command-2031) · transcript line 38451.


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


[Chat command 1293](docs/command-history.md#command-1293) · transcript line 27695.


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

The EC2 403s persisted because the role policy referred to a previous network. I compared the live VPC/subnets with `LaunchInterfacesInLabVpc`, `LaunchInTaggedSubnets` and `UseTaggedLabSecurityGroups`. I updated those exact conditions, reviewed the JSON and reapplied the bootstrap IAM policy. This was a bootstrap policy repair, not a patch to the deployed machines.


[Chat command 1428](docs/command-history.md#command-1428) · transcript line 30063.


```bash
aws ec2 describe-vpcs \
  --profile mds-devsecops-lab \
  --region us-east-1 \
  --filters "Name=tag:Project,Values=project-3-secure-cicd-pipeline" \
  --query 'Vpcs[].{VpcId:VpcId,Cidr:CidrBlock}' \
  --output table
```


[Chat command 1429](docs/command-history.md#command-1429) · transcript line 30081.


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


[Chat command 1217](docs/command-history.md#command-1217) · transcript line 26409.


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


[Chat command 1574](docs/command-history.md#command-1574) · transcript line 31845.


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

The first OIDC assumption failed because the trust subject did not match this repository's immutable owner/repository identifiers. I corrected the two trust files and updated the live roles. I subsequently repaired CloudWatch list scope, RDS subnet-group ARN, EC2 image ARN ownership and launch-time tagging permissions instead of attaching AdministratorAccess.


[Chat command 557](docs/command-history.md#command-557) · transcript line 15731.


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


[Chat command 559](docs/command-history.md#command-559) · transcript line 15771.


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


[Chat command 560](docs/command-history.md#command-560) · transcript line 15789.


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


[Chat command 588](docs/command-history.md#command-588) · transcript line 16194.


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

An S3 412 indicated an existing lock, not a permission denial. I checked for another live apply before unlocking the specific abandoned database operation. The following is the historical recovery command with its original lock ID; I never run it without establishing that the owning operation has ended.


[Chat command 1426](docs/command-history.md#command-1426) · transcript line 29924.


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

I distinguished a running EC2 instance from a healthy service. The useful diagnostics were service status/journal, HTTP checks and file-path execution permissions under the service account. The checks below exposed the CLI executable-path/traversal problem, which I corrected in the image source. I also learned that SSM shell commands are not guaranteed to use Bash: `set -o pipefail` failed under `/bin/sh`.


[Chat command 1584](docs/command-history.md#command-1584) · transcript line 32182.


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


[Chat command 1765](docs/command-history.md#command-1765) · transcript line 34424.


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


[Chat command 1766](docs/command-history.md#command-1766) · transcript line 34449.


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

SonarQube analysis succeeded but export failed when `actions-runner` could not execute AWS CLI. After the image permission fix, CloudWatch delivered its event. SNS still needed a confirmed subscription before email could arrive. I verified these stages separately instead of treating a missing email as proof of zero issues.


[Chat command 1997](docs/command-history.md#command-1997) · transcript line 37914.


```bash
gh run download 41656129319 \
  --name sonarqube-results \
  --dir reports/sonarqube-41656129319

cat reports/sonarqube-41656129319/summary.json
```


[Chat command 1998](docs/command-history.md#command-1998) · transcript line 37933.


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


[Chat command 1999](docs/command-history.md#command-1999) · transcript line 37950.


```bash
aws ssm get-command-invocation \
  --profile mds-devsecops-lab \
  --region us-east-1 \
  --command-id 9db1245b-815a-4a22-96b7-49db6c766f4a \
  --instance-id i-REPLACE_WITH_YOUR_ID \
  --query '{Status:Status,Output:StandardOutputContent,Errors:StandardErrorContent}' \
  --output json
```


[Chat command 2026](docs/command-history.md#command-2026) · transcript line 38354.


```bash
aws sns list-subscriptions-by-topic \
  --profile mds-devsecops-lab \
  --region us-east-1 \
  --topic-arn arn:aws:sns:us-east-1:YOUR_ACCOUNT_ID:project-3-secure-cicd-pipeline-scan-findings \
  --query 'Subscriptions[].{Protocol:Protocol,Status:SubscriptionArn}' \
  --output table
```


[Chat command 2027](docs/command-history.md#command-2027) · transcript line 38363.


```bash
aws logs describe-log-streams \
  --profile mds-devsecops-lab \
  --region us-east-1 \
  --log-group-name /project-3/pipeline/scans \
  --log-stream-name-prefix sonarqube-41671030481 \
  --query 'logStreams[].{Stream:logStreamName,LastEvent:lastEventTimestamp}' \
  --output table
```


[Chat command 2031](docs/command-history.md#command-2031) · transcript line 38451.


```bash
aws sns list-subscriptions-by-topic \
  --profile mds-devsecops-lab \
  --region us-east-1 \
  --topic-arn arn:aws:sns:us-east-1:YOUR_ACCOUNT_ID:project-3-secure-cicd-pipeline-scan-findings \
  --output json --no-cli-pager
```

I use three distinct outcomes: a completed scan with no findings, a completed scan with findings, and execution/reporting failure. Findings do not block deployment in this lab. A tool that cannot run, parse its report or deliver required reporting is an operational failure and remains visible. I tested the separate workflows first so I could identify these failures before combining them.

## Source coverage and supporting records

I used the two supplied text attachments and the earlier conversation. The larger attachment contains both visible command blocks and repository-tool file writes. I extracted the visible blocks into [command-history.md](docs/command-history.md), with original source-line references and exact duplicates collapsed, and decoded the repository file writes into [configuration-record.md](docs/configuration-record.md). The small identity/profile attachment supports step 1. The shared-chat URL is a source pointer; the attachments provide the locally readable record.

I retained historical IDs and failed attempts as evidence, omitted credential values, and labelled browser-only actions instead of fabricating commands for them. Where a complete command uses the same established command with a later run ID, I say so. Configuration definitions shown as HCL/YAML are file contents, not shell commands to paste directly into a terminal. I used the checked-in final files for the final build and preserved their development history separately.

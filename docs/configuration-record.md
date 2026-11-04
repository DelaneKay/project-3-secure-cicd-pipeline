# Project 3 — Configuration contents from the conversation

> Repository copy: AWS account/resource identifiers, internal host addresses, database endpoints and personal email addresses have been replaced with placeholders. I obtain their real values using the lookup commands shown before running the dependent command. These placeholders are not literal working AWS IDs.

I preserved the last complete contents for each file written through the repository integration in the supplied conversation. These complement the shell-created files in [the command history](command-history.md). This is a historical record: an earlier or temporary import workflow can be superseded by the current repository. I do not execute these contents as Bash unless the file is a shell script and the walkthrough calls for it. No source-of-truth decisions are changed by this documentation.


## `terraform/sonarqube/main.tf`

Recorded at transcript line 24020.


```hcl
data "aws_iam_policy_document" "ec2_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "sonarqube" {
  name               = "${var.project_name}-sonarqube"
  assume_role_policy = data.aws_iam_policy_document.ec2_trust.json

  tags = {
    Project     = var.project_name
    Environment = "lab"
    ManagedBy   = "Terraform"
  }
}

resource "aws_iam_role_policy_attachment" "sonarqube_ssm" {
  role       = aws_iam_role.sonarqube.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "sonarqube_runtime" {
  name = "sonarqube-runtime"
  role = aws_iam_role.sonarqube.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = data.terraform_remote_state.database.outputs.master_user_secret_arn
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:DescribeLogStreams", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/project-3/sonarqube:*"
      },
      {
        Effect   = "Allow"
        Action   = ["cloudwatch:PutMetricData"]
        Resource = "*"
        Condition = {
          StringEquals = {
            "cloudwatch:namespace" = "Project3/SonarQube"
          }
        }
      }
    ]
  })
}

resource "aws_iam_instance_profile" "sonarqube" {
  name = "${var.project_name}-sonarqube"
  role = aws_iam_role.sonarqube.name
}

resource "aws_instance" "sonarqube" {
  ami                    = data.aws_ami.sonarqube.id
  instance_type          = var.sonarqube_instance_type
  subnet_id              = data.terraform_remote_state.network.outputs.private_subnet_ids[0]
  vpc_security_group_ids = [data.terraform_remote_state.network.outputs.sonarqube_security_group_id]
  iam_instance_profile   = aws_iam_instance_profile.sonarqube.name

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }

  root_block_device {
    encrypted             = true
    volume_type           = "gp3"
    volume_size           = 30
    delete_on_termination = true
  }

  tags = {
    Name                      = "${var.project_name}-sonarqube"
    Project                   = var.project_name
    Environment               = "lab"
    ManagedBy                 = "Terraform"
    Image                     = "sonarqube"
    "sonarqube-db-host"       = data.terraform_remote_state.database.outputs.db_address
    "sonarqube-db-port"       = tostring(data.terraform_remote_state.database.outputs.db_port)
    "sonarqube-db-name"       = var.sonarqube_db_name
    "sonarqube-db-secret-arn" = data.terraform_remote_state.database.outputs.master_user_secret_arn
  }

  depends_on = [aws_iam_role_policy.sonarqube_runtime]
}

output "sonarqube_instance_id" {
  description = "EC2 instance ID running private SonarQube."
  value       = aws_instance.sonarqube.id
}

output "sonarqube_private_ip" {
  description = "Private IP of the SonarQube host."
  value       = aws_instance.sonarqube.private_ip
}
```


## `iam/terraform-github-oidc/apply-permissions.json`

Recorded at transcript line 30416.


```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "LaunchProjectAmis",
      "Effect": "Allow",
      "Action": [
        "ec2:RunInstances"
      ],
      "Resource": "arn:aws:ec2:us-east-1::image/ami-*",
      "Condition": {
        "StringEquals": {
          "aws:RequestedRegion": "us-east-1",
          "ec2:Owner": "YOUR_ACCOUNT_ID"
        }
      }
    },
    {
      "Sid": "LaunchApprovedInstances",
      "Effect": "Allow",
      "Action": [
        "ec2:RunInstances"
      ],
      "Resource": "arn:aws:ec2:us-east-1:YOUR_ACCOUNT_ID:instance/*",
      "Condition": {
        "StringEquals": {
          "aws:RequestedRegion": "us-east-1",
          "aws:RequestTag/Project": "project-3-secure-cicd-pipeline",
          "ec2:InstanceType": [
            "t3.small",
            "c7i-flex.large"
          ]
        }
      }
    },
    {
      "Sid": "LaunchInTaggedSubnets",
      "Effect": "Allow",
      "Action": [
        "ec2:RunInstances"
      ],
      "Resource": "arn:aws:ec2:us-east-1:YOUR_ACCOUNT_ID:subnet/*",
      "Condition": {
        "StringEquals": {
          "aws:RequestedRegion": "us-east-1",
          "ec2:ResourceTag/Project": "project-3-secure-cicd-pipeline",
          "ec2:Vpc": "arn:aws:ec2:us-east-1:YOUR_ACCOUNT_ID:vpc/vpc-REPLACE_WITH_YOUR_ID"
        }
      }
    },
    {
      "Sid": "UseTaggedLabSecurityGroups",
      "Effect": "Allow",
      "Action": [
        "ec2:RunInstances"
      ],
      "Resource": "arn:aws:ec2:us-east-1:YOUR_ACCOUNT_ID:security-group/*",
      "Condition": {
        "StringEquals": {
          "aws:RequestedRegion": "us-east-1",
          "ec2:ResourceTag/Project": "project-3-secure-cicd-pipeline",
          "ec2:Vpc": "arn:aws:ec2:us-east-1:YOUR_ACCOUNT_ID:vpc/vpc-REPLACE_WITH_YOUR_ID"
        }
      }
    },
    {
      "Sid": "LaunchInterfacesInLabVpc",
      "Effect": "Allow",
      "Action": [
        "ec2:RunInstances"
      ],
      "Resource": "arn:aws:ec2:us-east-1:YOUR_ACCOUNT_ID:network-interface/*",
      "Condition": {
        "StringEquals": {
          "aws:RequestedRegion": "us-east-1",
          "ec2:Vpc": "arn:aws:ec2:us-east-1:YOUR_ACCOUNT_ID:vpc/vpc-REPLACE_WITH_YOUR_ID",
          "ec2:Subnet": [
            "arn:aws:ec2:us-east-1:YOUR_ACCOUNT_ID:subnet/subnet-REPLACE_WITH_YOUR_ID",
            "arn:aws:ec2:us-east-1:YOUR_ACCOUNT_ID:subnet/subnet-REPLACE_WITH_YOUR_ID",
            "arn:aws:ec2:us-east-1:YOUR_ACCOUNT_ID:subnet/subnet-REPLACE_WITH_YOUR_ID",
            "arn:aws:ec2:us-east-1:YOUR_ACCOUNT_ID:subnet/subnet-REPLACE_WITH_YOUR_ID"
          ]
        }
      }
    },
    {
      "Sid": "LaunchEncryptedVolumes",
      "Effect": "Allow",
      "Action": [
        "ec2:RunInstances"
      ],
      "Resource": "arn:aws:ec2:us-east-1:YOUR_ACCOUNT_ID:volume/*",
      "Condition": {
        "StringEquals": {
          "aws:RequestedRegion": "us-east-1"
        },
        "Bool": {
          "ec2:Encrypted": "true"
        }
      }
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetBucketLocation"
      ],
      "Resource": "arn:aws:s3:::project-3-tfstate-YOUR_ACCOUNT_ID-us-east-1"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket"
      ],
      "Resource": "arn:aws:s3:::project-3-tfstate-YOUR_ACCOUNT_ID-us-east-1",
      "Condition": {
        "StringLike": {
          "s3:prefix": [
            "project-3/*"
          ]
        }
      }
    },
    {
      "Sid": "StateObjects",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject"
      ],
      "Resource": "arn:aws:s3:::project-3-tfstate-YOUR_ACCOUNT_ID-us-east-1/project-3/*/terraform.tfstate"
    },
    {
      "Sid": "StateLocks",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject"
      ],
      "Resource": "arn:aws:s3:::project-3-tfstate-YOUR_ACCOUNT_ID-us-east-1/project-3/*/terraform.tfstate.tflock"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ec2:Describe*",
        "rds:Describe*",
        "rds:ListTagsForResource"
      ],
      "Resource": "*"
    },
    {
      "Sid": "ManageNetwork",
      "Effect": "Allow",
      "Action": [
        "ec2:ModifyVpcAttribute",
        "ec2:DeleteVpc",
        "ec2:ModifySubnetAttribute",
        "ec2:DeleteSubnet",
        "ec2:AttachInternetGateway",
        "ec2:DetachInternetGateway",
        "ec2:DeleteInternetGateway",
        "ec2:CreateRoute",
        "ec2:DeleteRoute",
        "ec2:AssociateRouteTable",
        "ec2:DisassociateRouteTable",
        "ec2:DeleteRouteTable",
        "ec2:ModifyVpcEndpoint",
        "ec2:DeleteVpcEndpoints",
        "ec2:AuthorizeSecurityGroupIngress",
        "ec2:RevokeSecurityGroupIngress",
        "ec2:AuthorizeSecurityGroupEgress",
        "ec2:RevokeSecurityGroupEgress",
        "ec2:DeleteSecurityGroup",
        "ec2:TerminateInstances",
        "ec2:DeleteTags"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "aws:RequestedRegion": "us-east-1",
          "ec2:ResourceTag/Project": "project-3-secure-cicd-pipeline"
        }
      }
    },
    {
      "Sid": "ManageIAM",
      "Effect": "Allow",
      "Action": [
        "iam:CreateRole",
        "iam:DeleteRole",
        "iam:GetRole",
        "iam:UpdateAssumeRolePolicy",
        "iam:TagRole",
        "iam:UntagRole",
        "iam:PutRolePolicy",
        "iam:GetRolePolicy",
        "iam:DeleteRolePolicy",
        "iam:ListRolePolicies",
        "iam:ListAttachedRolePolicies",
        "iam:GetPolicy",
        "iam:GetPolicyVersion"
      ],
      "Resource": "arn:aws:iam::YOUR_ACCOUNT_ID:role/project-3-secure-cicd-pipeline-*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "iam:AttachRolePolicy",
        "iam:DetachRolePolicy"
      ],
      "Resource": [
        "arn:aws:iam::YOUR_ACCOUNT_ID:role/project-3-secure-cicd-pipeline-*",
        "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "iam:CreateInstanceProfile",
        "iam:DeleteInstanceProfile",
        "iam:GetInstanceProfile",
        "iam:AddRoleToInstanceProfile",
        "iam:RemoveRoleFromInstanceProfile",
        "iam:TagInstanceProfile",
        "iam:UntagInstanceProfile"
      ],
      "Resource": [
        "arn:aws:iam::YOUR_ACCOUNT_ID:instance-profile/project-3-secure-cicd-pipeline-*",
        "arn:aws:iam::YOUR_ACCOUNT_ID:role/project-3-secure-cicd-pipeline-*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "iam:ListInstanceProfilesForRole"
      ],
      "Resource": "arn:aws:iam::YOUR_ACCOUNT_ID:role/project-3-secure-cicd-pipeline-*"
    },
    {
      "Sid": "PassRoles",
      "Effect": "Allow",
      "Action": [
        "iam:PassRole"
      ],
      "Resource": "arn:aws:iam::YOUR_ACCOUNT_ID:role/project-3-secure-cicd-pipeline-*",
      "Condition": {
        "StringEquals": {
          "iam:PassedToService": "ec2.amazonaws.com"
        }
      }
    },
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:CreateSecret"
      ],
      "Resource": "*",
      "Condition": {
        "StringLike": {
          "secretsmanager:Name": "rds!*"
        }
      }
    },
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:TagResource"
      ],
      "Resource": "YOUR_SECRET_ARN"
    },
    {
      "Effect": "Allow",
      "Action": [
        "kms:DescribeKey"
      ],
      "Resource": "arn:aws:kms:us-east-1:YOUR_ACCOUNT_ID:key/*",
      "Condition": {
        "ForAnyValue:StringEquals": {
          "kms:ResourceAliases": "alias/aws/secretsmanager"
        }
      }
    },
    {
      "Sid": "SonarDB",
      "Effect": "Allow",
      "Action": [
        "rds:CreateDBInstance",
        "rds:ModifyDBInstance",
        "rds:DeleteDBInstance",
        "rds:AddTagsToResource",
        "rds:RemoveTagsFromResource",
        "rds:CreateDBSubnetGroup",
        "rds:ModifyDBSubnetGroup",
        "rds:DeleteDBSubnetGroup"
      ],
      "Resource": [
        "arn:aws:rds:us-east-1:YOUR_ACCOUNT_ID:db:project-3-sonarqube",
        "arn:aws:rds:us-east-1:YOUR_ACCOUNT_ID:subgrp:project-3-sonarqube-subnets"
      ],
      "Condition": {
        "StringEquals": {
          "aws:RequestedRegion": "us-east-1"
        }
      }
    },
    {
      "Effect": "Allow",
      "Action": [
        "iam:CreateServiceLinkedRole"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "iam:AWSServiceName": "rds.amazonaws.com"
        }
      }
    },
    {
      "Sid": "Logs",
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:DeleteLogGroup",
        "logs:PutRetentionPolicy",
        "logs:DeleteRetentionPolicy",
        "logs:ListTagsForResource",
        "logs:TagResource",
        "logs:UntagResource"
      ],
      "Resource": "arn:aws:logs:us-east-1:YOUR_ACCOUNT_ID:log-group:/project-3/*"
    },
    {
      "Sid": "ScanTopic",
      "Effect": "Allow",
      "Action": [
        "sns:CreateTopic",
        "sns:DeleteTopic",
        "sns:GetTopicAttributes",
        "sns:SetTopicAttributes",
        "sns:TagResource",
        "sns:UntagResource",
        "sns:Subscribe",
        "sns:Unsubscribe",
        "sns:GetSubscriptionAttributes",
        "sns:ListSubscriptionsByTopic",
        "sns:ListTagsForResource"
      ],
      "Resource": "arn:aws:sns:us-east-1:YOUR_ACCOUNT_ID:project-3-secure-cicd-pipeline-scan-findings"
    },
    {
      "Sid": "RunnerToken",
      "Effect": "Allow",
      "Action": [
        "ssm:PutParameter"
      ],
      "Resource": "arn:aws:ssm:us-east-1:YOUR_ACCOUNT_ID:parameter/project-3/github-runner/registration-token"
    },
    {
      "Effect": "Allow",
      "Action": [
        "sts:GetCallerIdentity"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ec2:CreateVpc",
        "ec2:CreateInternetGateway"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "aws:RequestTag/Project": "project-3-secure-cicd-pipeline",
          "aws:RequestedRegion": "us-east-1"
        }
      }
    },
    {
      "Effect": "Allow",
      "Action": [
        "ec2:CreateTags"
      ],
      "Resource": [
        "arn:aws:ec2:us-east-1:YOUR_ACCOUNT_ID:vpc/*",
        "arn:aws:ec2:us-east-1:YOUR_ACCOUNT_ID:subnet/*",
        "arn:aws:ec2:us-east-1:YOUR_ACCOUNT_ID:internet-gateway/*",
        "arn:aws:ec2:us-east-1:YOUR_ACCOUNT_ID:route-table/*",
        "arn:aws:ec2:us-east-1:YOUR_ACCOUNT_ID:security-group/*",
        "arn:aws:ec2:us-east-1:YOUR_ACCOUNT_ID:vpc-endpoint/*"
      ],
      "Condition": {
        "StringEquals": {
          "aws:RequestTag/Project": "project-3-secure-cicd-pipeline",
          "aws:RequestedRegion": "us-east-1"
        }
      }
    },
    {
      "Effect": "Allow",
      "Action": [
        "ec2:CreateSubnet"
      ],
      "Resource": "arn:aws:ec2:us-east-1:YOUR_ACCOUNT_ID:subnet/*",
      "Condition": {
        "StringEquals": {
          "aws:RequestTag/Project": "project-3-secure-cicd-pipeline",
          "aws:RequestedRegion": "us-east-1"
        }
      }
    },
    {
      "Effect": "Allow",
      "Action": [
        "ec2:CreateSubnet"
      ],
      "Resource": "arn:aws:ec2:us-east-1:YOUR_ACCOUNT_ID:vpc/*",
      "Condition": {
        "StringEquals": {
          "ec2:ResourceTag/Project": "project-3-secure-cicd-pipeline",
          "aws:RequestedRegion": "us-east-1"
        }
      }
    },
    {
      "Effect": "Allow",
      "Action": [
        "ec2:CreateRouteTable"
      ],
      "Resource": "arn:aws:ec2:us-east-1:YOUR_ACCOUNT_ID:route-table/*",
      "Condition": {
        "StringEquals": {
          "aws:RequestTag/Project": "project-3-secure-cicd-pipeline",
          "aws:RequestedRegion": "us-east-1"
        }
      }
    },
    {
      "Effect": "Allow",
      "Action": [
        "ec2:CreateRouteTable"
      ],
      "Resource": "arn:aws:ec2:us-east-1:YOUR_ACCOUNT_ID:vpc/*",
      "Condition": {
        "StringEquals": {
          "ec2:ResourceTag/Project": "project-3-secure-cicd-pipeline",
          "aws:RequestedRegion": "us-east-1"
        }
      }
    },
    {
      "Effect": "Allow",
      "Action": [
        "ec2:CreateSecurityGroup"
      ],
      "Resource": "arn:aws:ec2:us-east-1:YOUR_ACCOUNT_ID:security-group/*",
      "Condition": {
        "StringEquals": {
          "aws:RequestTag/Project": "project-3-secure-cicd-pipeline",
          "aws:RequestedRegion": "us-east-1"
        }
      }
    },
    {
      "Effect": "Allow",
      "Action": [
        "ec2:CreateSecurityGroup"
      ],
      "Resource": "arn:aws:ec2:us-east-1:YOUR_ACCOUNT_ID:vpc/*",
      "Condition": {
        "StringEquals": {
          "ec2:ResourceTag/Project": "project-3-secure-cicd-pipeline",
          "aws:RequestedRegion": "us-east-1"
        }
      }
    },
    {
      "Effect": "Allow",
      "Action": [
        "ec2:CreateVpcEndpoint"
      ],
      "Resource": "arn:aws:ec2:us-east-1:YOUR_ACCOUNT_ID:vpc-endpoint/*",
      "Condition": {
        "StringEquals": {
          "aws:RequestTag/Project": "project-3-secure-cicd-pipeline",
          "aws:RequestedRegion": "us-east-1"
        }
      }
    },
    {
      "Effect": "Allow",
      "Action": [
        "ec2:CreateVpcEndpoint"
      ],
      "Resource": [
        "arn:aws:ec2:us-east-1:YOUR_ACCOUNT_ID:route-table/*",
        "arn:aws:ec2:us-east-1:YOUR_ACCOUNT_ID:security-group/*",
        "arn:aws:ec2:us-east-1:YOUR_ACCOUNT_ID:subnet/*",
        "arn:aws:ec2:us-east-1:YOUR_ACCOUNT_ID:vpc/*"
      ],
      "Condition": {
        "StringEquals": {
          "ec2:ResourceTag/Project": "project-3-secure-cicd-pipeline",
          "aws:RequestedRegion": "us-east-1"
        }
      }
    },
    {
      "Effect": "Allow",
      "Action": [
        "logs:DescribeLogGroups"
      ],
      "Resource": "*"
    },
    {
      "Sid": "TagProjectInstancesWhenLaunched",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateTags"
      ],
      "Resource": "arn:aws:ec2:us-east-1:YOUR_ACCOUNT_ID:instance/*",
      "Condition": {
        "StringEquals": {
          "aws:RequestTag/Project": "project-3-secure-cicd-pipeline",
          "aws:RequestedRegion": "us-east-1",
          "ec2:CreateAction": "RunInstances"
        }
      }
    }
  ]
}
```


## `.github/workflows/terraform-import-existing-database.yml`

Recorded at transcript line 31416.


```yaml
name: Import existing SonarQube database into Terraform state

on:
  workflow_dispatch:
    inputs:
      confirmation:
        description: Type IMPORT-EXISTING-DATABASE to adopt the existing RDS resources into Terraform state.
        required: true
        type: string

permissions:
  contents: read
  id-token: write

# Share the deployment lock so import cannot overlap deploy or destroy workflows.
concurrency:
  group: project-3-terraform-deployment
  cancel-in-progress: false

jobs:
  import-database-state:
    if: github.ref == 'refs/heads/master'
    name: Import existing database resources into state
    runs-on: ubuntu-24.04
    environment: terraform-lab-apply
    permissions:
      contents: read
      id-token: write
    steps:
      - name: Require explicit import confirmation
        shell: bash
        env:
          CONFIRMATION: ${{ inputs.confirmation }}
        run: |
          if [[ "$CONFIRMATION" != "IMPORT-EXISTING-DATABASE" ]]; then
            echo "Enter IMPORT-EXISTING-DATABASE to continue." >&2
            exit 1
          fi

      - name: Check out source
        uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683

      - name: Set up Terraform
        uses: hashicorp/setup-terraform@b9cd54a3c349d3f38e8881555d616ced269862dd
        with:
          terraform_version: 1.16.2
          terraform_wrapper: false

      - name: Configure AWS apply role with GitHub OIDC
        uses: aws-actions/configure-aws-credentials@e3dd6a429d7300a6a4c196c26e071d42e0343502
        with:
          role-to-assume: ${{ vars.AWS_TERRAFORM_APPLY_ROLE_ARN }}
          aws-region: us-east-1
          role-session-name: terraform-import-sonarqube-db

      - name: Initialize database state and import only if missing
        shell: bash
        env:
          TF_STATE_BUCKET: ${{ vars.TF_STATE_BUCKET }}
          AWS_REGION: us-east-1
        run: |
          set -Eeuo pipefail
          root="terraform/database"

          terraform -chdir="$root" init -input=false -lock-timeout=5m \
            -backend-config="bucket=$TF_STATE_BUCKET" \
            -backend-config="key=project-3/database/terraform.tfstate" \
            -backend-config="region=$AWS_REGION" \
            -backend-config="use_lockfile=true"

          import_if_missing() {
            local address="$1"
            local resource_id="$2"
            local current_state

            current_state="$(terraform -chdir="$root" state list)"
            if grep -Fxq "$address" <<<"$current_state"; then
              echo "$address is already tracked; skipping import."
              return
            fi

            echo "Importing existing AWS resource into Terraform state: $address"
            terraform -chdir="$root" import -input=false -lock-timeout=5m \
              "$address" "$resource_id"
          }

          # Import the subnet group before the database instance that references it.
          import_if_missing \
            "aws_db_subnet_group.sonarqube" \
            "project-3-sonarqube-subnets"
          import_if_missing \
            "aws_db_instance.sonarqube" \
            "project-3-sonarqube"

          echo "State adoption complete. No AWS infrastructure was created, updated, or deleted."
```


## `.github/workflows/database-state-import.yml`

Recorded at transcript line 31490.


```yaml
name: Import existing SonarQube database into Terraform state

on:
  workflow_dispatch:
    inputs:
      confirmation:
        description: Type IMPORT-EXISTING-DATABASE to adopt the existing RDS resources into Terraform state.
        required: true
        type: string

permissions:
  contents: read
  id-token: write

# Share the deployment lock so import cannot overlap deploy or destroy workflows.
concurrency:
  group: project-3-terraform-deployment
  cancel-in-progress: false

jobs:
  import-database-state:
    if: github.ref == 'refs/heads/master'
    name: Import existing database resources into state
    runs-on: ubuntu-24.04
    environment: terraform-lab-apply
    permissions:
      contents: read
      id-token: write
    steps:
      - name: Require explicit import confirmation
        shell: bash
        env:
          CONFIRMATION: ${{ inputs.confirmation }}
        run: |
          if [[ "$CONFIRMATION" != "IMPORT-EXISTING-DATABASE" ]]; then
            echo "Enter IMPORT-EXISTING-DATABASE to continue." >&2
            exit 1
          fi

      - name: Check out source
        uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683

      - name: Set up Terraform
        uses: hashicorp/setup-terraform@b9cd54a3c349d3f38e8881555d616ced269862dd
        with:
          terraform_version: 1.16.2
          terraform_wrapper: false

      - name: Configure AWS apply role with GitHub OIDC
        uses: aws-actions/configure-aws-credentials@e3dd6a429d7300a6a4c196c26e071d42e0343502
        with:
          role-to-assume: ${{ vars.AWS_TERRAFORM_APPLY_ROLE_ARN }}
          aws-region: us-east-1
          role-session-name: terraform-import-sonarqube-db

      - name: Initialize database state and import only if missing
        shell: bash
        env:
          TF_STATE_BUCKET: ${{ vars.TF_STATE_BUCKET }}
          AWS_REGION: us-east-1
        run: |
          set -Eeuo pipefail
          root="terraform/database"

          terraform -chdir="$root" init -input=false -lock-timeout=5m \
            -backend-config="bucket=$TF_STATE_BUCKET" \
            -backend-config="key=project-3/database/terraform.tfstate" \
            -backend-config="region=$AWS_REGION" \
            -backend-config="use_lockfile=true"

          import_if_missing() {
            local address="$1"
            local resource_id="$2"
            local current_state

            current_state="$(terraform -chdir="$root" state list)"
            if grep -Fxq "$address" <<<"$current_state"; then
              echo "$address is already tracked; skipping import."
              return
            fi

            echo "Importing existing AWS resource into Terraform state: $address"
            terraform -chdir="$root" import -input=false -lock-timeout=5m \
              "$address" "$resource_id"
          }

          # Import the subnet group before the database instance that references it.
          import_if_missing \
            "aws_db_subnet_group.sonarqube" \
            "project-3-sonarqube-subnets"
          import_if_missing \
            "aws_db_instance.sonarqube" \
            "project-3-sonarqube"

          echo "State adoption complete. No AWS infrastructure was created, updated, or deleted."
```


## `packer/sonarqube/scripts/start-sonarqube.sh`

Recorded at transcript line 32442.


```bash
#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

IMDS="http://169.254.169.254"
TOKEN_TTL_SECONDS=21600
MAX_SECRET_ATTEMPTS=12
SECRET_RETRY_SECONDS=10

log() {
  printf 'sonarqube-launcher: %s\n' "$*" >&2
}

classify_secret_error() {
  local error_file="$1"

  if grep -Eqi 'AccessDeniedException|not authorized|AccessDenied' "$error_file"; then
    printf 'authorization'
  elif grep -Eqi 'Could not connect to the endpoint URL|EndpointConnectionError|Connect timeout|Could not resolve|Name or service not known|Temporary failure in name resolution|Network is unreachable|Connection timed out' "$error_file"; then
    printf 'network-or-dns'
  elif grep -Eqi 'ResourceNotFoundException|Secrets Manager can.t find the specified secret' "$error_file"; then
    printf 'secret-not-found'
  elif grep -Eqi 'Unable to locate credentials|NoCredentialsError|InvalidClientTokenId|UnrecognizedClientException|ExpiredToken' "$error_file"; then
    printf 'instance-role-credentials'
  elif grep -Eqi 'ValidationException|InvalidParameter' "$error_file"; then
    printf 'invalid-secret-reference-or-request'
  elif grep -Eqi 'aws: command not found|command not found' "$error_file"; then
    printf 'aws-cli-unavailable'
  else
    printf 'other-aws-cli-error'
  fi
}

IMDS_TOKEN="$(curl --fail --silent --show-error \
  --connect-timeout 2 \
  --max-time 5 \
  --request PUT \
  --header "X-aws-ec2-metadata-token-ttl-seconds: ${TOKEN_TTL_SECONDS}" \
  "${IMDS}/latest/api/token")"

IMDS_HEADER="X-aws-ec2-metadata-token: ${IMDS_TOKEN}"

get_instance_tag() {
  local tag_name="$1"
  curl --fail --silent --show-error \
    --connect-timeout 2 \
    --max-time 5 \
    --header "${IMDS_HEADER}" \
    "${IMDS}/latest/meta-data/tags/instance/${tag_name}"
}

IDENTITY_DOCUMENT="$(curl --fail --silent --show-error \
  --connect-timeout 2 \
  --max-time 5 \
  --header "${IMDS_HEADER}" \
  "${IMDS}/latest/dynamic/instance-identity/document")"

AWS_REGION="$(jq -er '.region' <<<"${IDENTITY_DOCUMENT}")"
DB_HOST="$(get_instance_tag sonarqube-db-host)"
DB_PORT="$(get_instance_tag sonarqube-db-port)"
DB_NAME="$(get_instance_tag sonarqube-db-name)"
SECRET_ARN="$(get_instance_tag sonarqube-db-secret-arn)"

if [[ ! "${DB_PORT}" =~ ^[0-9]{1,5}$ ]] || (( DB_PORT < 1 || DB_PORT > 65535 )); then
  log "Database port metadata is invalid."
  exit 1
fi

if [[ -z "${DB_HOST}" || -z "${DB_NAME}" || -z "${SECRET_ARN}" ]]; then
  log "Required database connection metadata is missing."
  exit 1
fi

AWS_CLI_BIN=""
for candidate in \
  /usr/local/aws-cli/v2/current/bin/aws \
  /usr/local/bin/aws \
  /usr/bin/aws; do
  if [[ -x "$candidate" ]]; then
    AWS_CLI_BIN="$candidate"
    break
  fi
done

if [[ -z "$AWS_CLI_BIN" ]]; then
  log "AWS CLI executable was not found in its expected installation paths."
  exit 1
fi

if ! "$AWS_CLI_BIN" --version >/dev/null 2>&1; then
  log "AWS CLI executable was found but could not run."
  exit 1
fi

AWS_ERROR_FILE="$(mktemp)"
trap 'rm -f "$AWS_ERROR_FILE"' EXIT

SECRET_JSON=""
for ((attempt = 1; attempt <= MAX_SECRET_ATTEMPTS; attempt++)); do
  : >"${AWS_ERROR_FILE}"

  if SECRET_JSON="$("$AWS_CLI_BIN" secretsmanager get-secret-value \
      --region "${AWS_REGION}" \
      --secret-id "${SECRET_ARN}" \
      --query SecretString \
      --output text 2>"${AWS_ERROR_FILE}")"; then
    break
  fi

  ERROR_CATEGORY="$(classify_secret_error "${AWS_ERROR_FILE}")"
  if (( attempt == MAX_SECRET_ATTEMPTS )); then
    log "Secrets Manager request failed after ${MAX_SECRET_ATTEMPTS} attempts (category=${ERROR_CATEGORY})."
    exit 1
  fi

  log "Secrets Manager request failed (category=${ERROR_CATEGORY}); retry ${attempt}/${MAX_SECRET_ATTEMPTS}."
  sleep "${SECRET_RETRY_SECONDS}"
done

export SONAR_JDBC_URL="jdbc:postgresql://${DB_HOST}:${DB_PORT}/${DB_NAME}"
export SONAR_JDBC_USERNAME="$(jq -er '.username' <<<"${SECRET_JSON}")"
export SONAR_JDBC_PASSWORD="$(jq -er '.password' <<<"${SECRET_JSON}")"
unset SECRET_JSON IDENTITY_DOCUMENT IMDS_TOKEN IMDS_HEADER

SONARQUBE_JAR="$(find /opt/sonarqube/lib \
  -maxdepth 1 \
  -type f \
  -name 'sonar-application-*.jar' \
  -print -quit)"

if [[ -z "${SONARQUBE_JAR}" ]]; then
  log "SonarQube application JAR was not found."
  exit 1
fi

exec /usr/bin/java \
  -Xms32m \
  -Xmx32m \
  -Djava.net.preferIPv4Stack=true \
  -jar "${SONARQUBE_JAR}"
```


## `packer/sonarqube/scripts/install-sonarqube.sh`

Recorded at transcript line 34607.


```bash
#!/usr/bin/env bash
set -euo pipefail
umask 027

SONARQUBE_VERSION="${SONARQUBE_VERSION:-26.10.0.133078}"
JAVA_PACKAGE="${JAVA_PACKAGE:-openjdk-21-jdk}"
AWS_CLI_VERSION="${AWS_CLI_VERSION:-2.39.1}"
AWS_CLI_KEY_ID="A6310ACC4672475C"
AWS_CLI_KEY_FINGERPRINT="FB5DB77FD5C118B80511ADA8A6310ACC4672475C"

SONARQUBE_URL="https://binaries.sonarsource.com/Distribution/sonarqube/sonarqube-${SONARQUBE_VERSION}.zip"
AWS_CLI_ARCHIVE="awscli-exe-linux-x86_64-${AWS_CLI_VERSION}.zip"
AWS_CLI_URL="https://awscli.amazonaws.com/${AWS_CLI_ARCHIVE}"

WORK_DIR="$(mktemp -d)"
SONARQUBE_JAR=""

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

download() {
  local label="$1"
  local url="$2"
  local destination="$3"
  local http_status

  printf '\nDownloading %s\nURL: %s\n' "$label" "$url"
  if http_status="$(curl \
    --fail \
    --silent \
    --show-error \
    --location \
    --retry 3 \
    --connect-timeout 20 \
    --max-time 600 \
    --output "$destination" \
    --write-out '%{http_code}' \
    "$url")"; then
    printf 'Download succeeded: %s (HTTP %s)\n' "$label" "$http_status"
  else
    printf 'Download failed: %s (HTTP %s)\nURL: %s\n' \
      "$label" "${http_status:-unknown}" "$url" >&2
    return 1
  fi
}

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get full-upgrade -y
apt-get install -y \
  ca-certificates \
  curl \
  gnupg \
  jq \
  unzip \
  "$JAVA_PACKAGE"

java -version

download \
  "AWS CLI v${AWS_CLI_VERSION} archive" \
  "$AWS_CLI_URL" \
  "$WORK_DIR/awscli.zip"

download \
  "AWS CLI v${AWS_CLI_VERSION} signature" \
  "${AWS_CLI_URL}.sig" \
  "$WORK_DIR/awscli.zip.sig"

cat > "$WORK_DIR/aws-cli-public-key.asc" <<'PGP'
-----BEGIN PGP PUBLIC KEY BLOCK-----

mQINBF2Cr7UBEADJZHcgusOJl7ENSyumXh85z0TRV0xJorM2B/JL0kHOyigQluUG
ZMLhENaG0bYatdrKP+3H91lvK050pXwnO/R7fB/FSTouki4ciIx5OuLlnJZIxSzx
PqGl0mkxImLNbGWoi6Lto0LYxqHN2iQtzlwTVmq9733zd3XfcXrZ3+LblHAgEt5G
TfNxEKJ8soPLyWmwDH6HWCnjZ/aIQRBTIQ05uVeEoYxSh6wOai7ss/KveoSNBbYz
gbdzoqI2Y8cgH2nbfgp3DSasaLZEdCSsIsK1u05CinE7k2qZ7KgKAUIcT/cR/grk
C6VwsnDU0OUCideXcQ8WeHutqvgZH1JgKDbznoIzeQHJD238GEu+eKhRHcz8/jeG
94zkcgJOz3KbZGYMiTh277Fvj9zzvZsbMBCedV1BTg3TqgvdX4bdkhf5cH+7NtWO
lrFj6UwAsGukBTAOxC0l/dnSmZhJ7Z1KmEWilro/gOrjtOxqRQutlIqG22TaqoPG
fYVN+en3Zwbt97kcgZDwqbuykNt64oZWc4XKCa3mprEGC3IbJTBFqglXmZ7l9ywG
EEUJYOlb2XrSuPWml39beWdKM8kzr1OjnlOm6+lpTRCBfo0wa9F8YZRhHPAkwKkX
XDeOGpWRj4ohOx0d2GWkyV5xyN14p2tQOCdOODmz80yUTgRpPVQUtOEhXQARAQAB
tCFBV1MgQ0xJIFRlYW0gPGF3cy1jbGlAYW1hem9uLmNvbT6JAlQEEwEIAD4CGwMF
CwkIBwIGFQoJCAsCBBYCAwECHgECF4AWIQT7Xbd/1cEYuAURraimMQrMRnJHXAUC
akV0ygUJDqP4lQAKCRCmMQrMRnJHXFHjD/9eyZLYcKuQOlLvtqSDtUBiEZf6ZZjM
i3ygYH8rJNtuToUH+HvSpe819urJCquXhDrlK6N+aqW0hCLtNABJG/vsafIgvIYJ
hSGgpgtNnQyMV1jViRWqPjbouw8OkYKBThUfT1i2Y+wn58ifs6ODBCmTexWtXspA
Si+Gt49xDOW0APmbOPnI+a4HJW6tVEo6MWS0WjzpiBayR3d1A4pt4YrPfSdDgpLo
h2SLQqlRqvvVZJaWBjhkErNFpfsBA06sDcPEOb0G8LBUbR4WOcdvhe5LubJbZuxC
AG9kNPCVeQP1ixwjgjXKysaxeQ6rv0VzIQgRp6tLVLWhy6AKDNvLjFSsmXZ1Wl08
Y/RlOHXlzLuQMRE6sR1wOdRxc9TsrNWTGiBK65cvSWOy03JeBkQQ8pesqltiyxI9
U21kkgiXtTSKNGfKK8pO27D81YANhRqPK7iTp6kuFiY2WtOg90KTMNlIT+Ff85Y2
b1rHj6Z0SrCkJujhWk3IBPic/wJgz01LEc/OAdUPlby90RJZcIBhSlWhT7mXnXIO
c0HWlNQrns2s3CTyYwZSiSlYe9ApeLwhjDo8NhbFuCAy61l6O5UsR4AfZxx/rGKv
2wFb1/RN/P4gNe6vmxZAPjR0AQcwD3tc2McimOLr/22kmPz8IH3I0X7WoSFr0Biz
E91G7bb0hOb/cA==
=knv7
-----END PGP PUBLIC KEY BLOCK-----
PGP

GNUPGHOME="$WORK_DIR/gnupg"
install -d -m 0700 "$GNUPGHOME"
export GNUPGHOME

gpg --batch --import "$WORK_DIR/aws-cli-public-key.asc"

actual_fingerprint="$(
  gpg --batch --with-colons --fingerprint "$AWS_CLI_KEY_ID" \
    | awk -F: '$1 == "fpr" { print $10; exit }'
)"

if [[ "$actual_fingerprint" != "$AWS_CLI_KEY_FINGERPRINT" ]]; then
  echo "AWS CLI signing key fingerprint did not match the expected value." >&2
  echo "Expected: $AWS_CLI_KEY_FINGERPRINT" >&2
  echo "Actual:   $actual_fingerprint" >&2
  exit 1
fi

if ! verify_output="$(
  gpg --batch --status-fd 1 \
    --verify "$WORK_DIR/awscli.zip.sig" "$WORK_DIR/awscli.zip" 2>&1
)"; then
  printf '%s\n' "$verify_output" >&2
  echo "AWS CLI archive signature verification failed." >&2
  exit 1
fi

printf '%s\n' "$verify_output"
if ! grep -Fq "[GNUPG:] VALIDSIG ${AWS_CLI_KEY_FINGERPRINT}" <<<"$verify_output"; then
  echo "AWS CLI archive was not signed by the expected AWS CLI key." >&2
  exit 1
fi

unzip -q "$WORK_DIR/awscli.zip" -d "$WORK_DIR/awscli"
"$WORK_DIR/awscli/aws/install" \
  --install-dir /usr/local/aws-cli \
  --bin-dir /usr/local/bin

aws_cli_output="$(aws --version 2>&1)"
printf '%s\n' "$aws_cli_output"

if [[ "$aws_cli_output" != "aws-cli/${AWS_CLI_VERSION}"* ]]; then
  echo "Installed AWS CLI version did not match ${AWS_CLI_VERSION}." >&2
  exit 1
fi

AWS_CLI_BIN="/usr/local/aws-cli/v2/current/bin/aws"
if [[ ! -x "$AWS_CLI_BIN" ]]; then
  echo "AWS CLI executable is missing from the expected installation path: $AWS_CLI_BIN" >&2
  exit 1
fi

"$AWS_CLI_BIN" --version

download \
  "SonarQube v${SONARQUBE_VERSION} archive" \
  "$SONARQUBE_URL" \
  "$WORK_DIR/sonarqube.zip"

download \
  "SonarQube v${SONARQUBE_VERSION} SHA-256 checksum" \
  "${SONARQUBE_URL}.sha256" \
  "$WORK_DIR/sonarqube.zip.sha256"

expected_checksum="$(
  grep -Eo '[[:xdigit:]]{64}' "$WORK_DIR/sonarqube.zip.sha256" | sed -n '1p'
)"

if [[ ! "$expected_checksum" =~ ^[[:xdigit:]]{64}$ ]]; then
  echo "Could not read the SonarQube SHA-256 checksum." >&2
  cat "$WORK_DIR/sonarqube.zip.sha256" >&2
  exit 1
fi

printf '%s  %s\n' "$expected_checksum" "$WORK_DIR/sonarqube.zip" \
  | sha256sum --check

groupadd --system sonarqube 2>/dev/null || true

useradd \
  --system \
  --gid sonarqube \
  --home-dir /var/lib/sonarqube \
  --create-home \
  --shell /usr/sbin/nologin \
  sonarqube 2>/dev/null || true

# Keep the AWS CLI private to the SonarQube service group while allowing the
# service account to traverse its directories, read its runtime files, and run it.
chgrp -R sonarqube /usr/local/aws-cli
chmod -R g+rX,g-w,o-rwx /usr/local/aws-cli

if ! runuser -u sonarqube -- "$AWS_CLI_BIN" --version; then
  echo "AWS CLI cannot run as the sonarqube service user." >&2
  exit 1
fi

unzip -q "$WORK_DIR/sonarqube.zip" -d /opt
SONARQUBE_HOME="/opt/sonarqube-${SONARQUBE_VERSION}"
ln -sfn "$SONARQUBE_HOME" /opt/sonarqube
chown -R sonarqube:sonarqube "$SONARQUBE_HOME"

SONARQUBE_JAR="$(
  find "$SONARQUBE_HOME/lib" \
    -maxdepth 1 \
    -type f \
    -name 'sonar-application-*.jar' \
    -print -quit
)"

if [[ -z "$SONARQUBE_JAR" ]]; then
  echo "SonarQube application JAR was not found." >&2
  exit 1
fi

if [[ ! -f /tmp/project-3-start-sonarqube ]]; then
  echo "Packer did not stage the SonarQube startup launcher." >&2
  exit 1
fi

install -o root -g root -m 0755 \
  /tmp/project-3-start-sonarqube \
  /usr/local/sbin/project-3-start-sonarqube
rm -f /tmp/project-3-start-sonarqube

cat > /etc/sysctl.d/99-sonarqube.conf <<'SYSCTL'
vm.max_map_count=524288
fs.file-max=131072
SYSCTL

sysctl --system

cat > /etc/systemd/system/sonarqube.service <<'UNIT'
[Unit]
Description=SonarQube Community Build
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=sonarqube
Group=sonarqube
WorkingDirectory=/opt/sonarqube
ExecStart=/usr/local/sbin/project-3-start-sonarqube
SuccessExitStatus=143
Restart=on-failure
RestartSec=10
TimeoutStartSec=300
LimitNOFILE=131072
LimitNPROC=8192
UMask=0027
PrivateTmp=true

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable sonarqube.service

echo "SonarQube ${SONARQUBE_VERSION} and AWS CLI ${AWS_CLI_VERSION} installed."
echo "The baked service retrieves DB settings from instance metadata and credentials from Secrets Manager at startup."
```


## `packer/sonarqube/sonarqube.pkr.hcl`

Recorded at transcript line 35302.


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

variable "ssh_timeout" {
  type    = string
  default = "10m"
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
  ssh_timeout               = var.ssh_timeout
  pause_before_ssm          = "30s"
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

  provisioner "file" {
    source      = "${path.root}/scripts/start-sonarqube.sh"
    destination = "/tmp/project-3-start-sonarqube"
  }

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
  # Run last so the image is checked after every installation provisioner.
  provisioner "shell" {
    inline = [
      "set -eu",
      "test -d /usr/local/aws-cli",
      "chown -R root:root /usr/local/aws-cli",
      "chmod -R a+rX,u+w,go-w /usr/local/aws-cli",
      "test -x /usr/local/aws-cli/v2/current/bin/aws",
      "runuser -u sonarqube -- /bin/bash -c 'test -x /usr/local/aws-cli/v2/current/bin/aws && /usr/local/aws-cli/v2/current/bin/aws --version'",
      "systemctl is-enabled sonarqube.service",
    ]
    execute_command = "sudo -E bash '{{ .Path }}'"
  }

}
```


## `.github/workflows/sonarqube-setup.yml`

Recorded at transcript line 36029.


```yaml
name: SonarQube project setup

on:
  workflow_dispatch:

permissions:
  contents: read

concurrency:
  group: sonarqube-project-configuration
  cancel-in-progress: false

jobs:
  configure:
    if: github.ref == 'refs/heads/master'
    environment: sonarqube-admin
    runs-on: [self-hosted, linux, x64, project-3-scanner]
    timeout-minutes: 10
    env:
      SONAR_HOST_URL: ${{ vars.SONAR_HOST_URL }}
      SONAR_ADMIN_TOKEN: ${{ secrets.SONAR_ADMIN_TOKEN }}
    steps:
      - name: Check out trusted configuration
        uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683
        with:
          persist-credentials: false
      - name: Reconcile project and quality profiles
        run: python3 scripts/configure-sonarqube.py
      - name: Upload configuration receipt
        uses: actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02
        with:
          name: sonarqube-setup
          path: sonarqube-setup.json
          retention-days: 7
```


## `scripts/configure-sonarqube.py`

Recorded at transcript line 36501.


```python
#!/usr/bin/env python3
"""Reconcile SonarQube project configuration without changing the EC2 host."""
import json
import os
import time
import urllib.error
import urllib.parse
import urllib.request

host = os.environ["SONAR_HOST_URL"].rstrip("/")
parsed = urllib.parse.urlsplit(host)
if parsed.scheme not in ("http", "https") or not parsed.hostname or parsed.username or parsed.query or parsed.fragment:
    raise SystemExit("Set SONAR_HOST_URL to the private SonarQube service URL.")
token = os.environ.get("SONAR_ADMIN_TOKEN", "")
if not token:
    raise SystemExit("SONAR_ADMIN_TOKEN must be configured in the protected environment.")
project = "project-3-juice-shop"
opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))

def api(path, data=None):
    body = urllib.parse.urlencode(data).encode() if data is not None else None
    request = urllib.request.Request(host + path, data=body,
        headers={"Authorization": "Bearer " + token})
    try:
        with opener.open(request, timeout=20) as response:
            raw = response.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as error:
        # Never print response bodies, which may contain confidential details.
        raise RuntimeError(f"SonarQube API {path.split('?')[0]} returned HTTP {error.code}") from None

for attempt in range(30):
    try:
        if api("/api/system/status").get("status") == "UP":
            break
    except (RuntimeError, urllib.error.URLError, TimeoutError):
        pass
    time.sleep(5)
else:
    raise SystemExit("SonarQube did not become healthy.")

if api("/api/authentication/validate").get("valid") is not True:
    raise SystemExit("SonarQube administrative authentication failed.")

existing = api("/api/projects/search?" + urllib.parse.urlencode({"projects": project}))
if not any(item["key"] == project for item in existing.get("components", [])):
    api("/api/projects/create", {"project": project, "name": "Project 3 OWASP Juice Shop", "visibility": "private"})

# Use the installed version's built-in defaults rather than hard-coded names.
# Default profiles apply automatically; SonarQube may prohibit explicit binding
# to a default profile, so verify the project's effective profile instead.
selected = {}
for language in ("js", "ts", "web", "css"):
    profiles = api("/api/qualityprofiles/search?" + urllib.parse.urlencode({"language": language}))
    defaults = [p for p in profiles.get("profiles", [])
                if p.get("language") == language and p.get("isDefault") is True
                and p.get("isBuiltIn") is True]
    if len(defaults) != 1:
        raise SystemExit(f"Expected one built-in default profile for {language}.")
    chosen = defaults[0]
    effective = api("/api/qualityprofiles/search?" + urllib.parse.urlencode(
        {"project": project, "language": language}))
    matches = [p for p in effective.get("profiles", [])
               if p.get("language") == language]
    if len(matches) != 1 or matches[0].get("key") != chosen["key"]:
        raise SystemExit(
            f"Project profile for {language} differs from the built-in default; review its explicit association.")
    selected[language] = {"name": chosen["name"], "key": chosen["key"],
                          "activeRuleCount": chosen.get("activeRuleCount")}
    print(f"{language}: verified effective profile {chosen['name']}")

with open("sonarqube-setup.json", "w", encoding="utf-8") as report:
    json.dump({"project": project, "profiles": selected,
               "mode": "report-only", "setup": "complete"}, report, indent=2)
print("SonarQube project and effective default profiles verified successfully.")
```


## `terraform/compute/variables.tf`

Recorded at transcript line 37050.


```hcl
variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "tf_state_bucket" {
  type    = string
  default = "project-3-tfstate-YOUR_ACCOUNT_ID-us-east-1"
}

variable "project_name" {
  type    = string
  default = "project-3-secure-cicd-pipeline"
}

variable "juice_shop_instance_type" {
  type    = string
  default = "t3.small"
}

variable "runner_instance_type" {
  type    = string
  default = "c7i-flex.large"
}

variable "runner_registration_token_parameter" {
  description = "SSM SecureString parameter holding a fresh GitHub runner registration token."
  type        = string
  default     = "/project-3/github-runner/registration-token"
}
```


## `terraform/compute/instances.tf`

Recorded at transcript line 37267.


```hcl
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

resource "terraform_data" "runner_instance_type" {
  triggers_replace = {
    instance_type = var.runner_instance_type
    revision      = "immutable-sizing-v2"
  }
}

resource "aws_instance" "github_runner" {
  # Replace from the AMI when sizing changes, preserving immutable deployment.
  lifecycle {
    replace_triggered_by = [terraform_data.runner_instance_type]
  }

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
```


## `scripts/report-sonarqube.py`

Recorded at transcript line 37561.


```python
#!/usr/bin/env python3
"""Collect one analysis and publish only aggregate scan information."""
import collections
import csv
import datetime
import json
import os
import pathlib
import subprocess
import time
import urllib.parse
import urllib.request

out = pathlib.Path(os.environ["REPORT_DIR"])
out.mkdir(parents=True, exist_ok=True)
project = "project-3-juice-shop"
host = os.environ["SONAR_HOST_URL"].rstrip("/")
token = os.environ.get("SONAR_REPORT_TOKEN", "")
summary = {"tool": "SonarQube", "project": project, "status": "execution_failed",
           "run": os.environ["RUN_URL"], "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat(),
           "dashboard": host + "/dashboard?id=" + project}
commit_file = out / "source-commit.txt"
if commit_file.exists():
    summary["source_commit"] = commit_file.read_text().strip()

def api(path, **params):
    if not token:
        raise RuntimeError("Reporting credential missing")
    req = urllib.request.Request(host + path + "?" + urllib.parse.urlencode(params),
                                 headers={"Authorization": "Bearer " + token})
    # Use only the configured host, never URLs supplied in task metadata.
    with urllib.request.urlopen(req, timeout=30) as response:
        return json.load(response)

failed = False
try:
    if os.environ["SCAN_OUTCOME"] != "success":
        raise RuntimeError("Scanner execution failed")
    task = dict(line.split("=", 1) for line in (out / "report-task.txt").read_text().splitlines() if "=" in line)
    for _ in range(120):
        result = api("/api/ce/task", id=task["ceTaskId"])["task"]
        if result["status"] == "SUCCESS":
            analysis_id = result["analysisId"]
            break
        if result["status"] in ("FAILED", "CANCELED"):
            raise RuntimeError("Server analysis processing failed")
        time.sleep(5)
    else:
        raise RuntimeError("Server processing timeout")
    gate = api("/api/qualitygates/project_status", analysisId=analysis_id)["projectStatus"]
    issues = []
    page = 1
    while True:
        result = api("/api/issues/search", componentKeys=project, resolved="false", p=page, ps=500)
        issues.extend(result["issues"])
        total = result.get("paging", {}).get("total", result.get("total", 0))
        if len(issues) >= total:
            break
        if not result["issues"] or page >= 20:
            raise RuntimeError("Issue export incomplete; API pagination limit reached")
        page += 1
    # Keep a useful subset; omit source excerpts and issue messages.
    fields = ["key", "rule", "severity", "type", "component", "line", "status"]
    rows = [{key: issue.get(key, "") for key in fields} for issue in issues]
    (out / "issues.json").write_text(json.dumps(rows, indent=2))
    with (out / "issues.csv").open("w", newline="") as file:
        writer = csv.DictWriter(file, fieldnames=fields)
        writer.writeheader()
        # Prevent spreadsheet formula execution from string fields.
        writer.writerows({k: ("'" + v if isinstance(v, str) and v.startswith(("=", "+", "-", "@")) else v)
                          for k, v in row.items()} for row in rows)
    (out / "quality-status.json").write_text(json.dumps(gate, indent=2))
    summary.update(status="completed", analysis_id=analysis_id, issue_count=len(rows),
                   severities=dict(collections.Counter(row["severity"] for row in rows)),
                   quality_status=gate["status"])
except Exception as error:
    failed = True
    # Do not print API responses or credentials.
    summary["error_category"] = type(error).__name__
    print("Scan/report collection failed; see workflow steps and server task status.")

(out / "summary.json").write_text(json.dumps(summary, indent=2))
with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as file:
    file.write("### SonarQube result\n\n" + json.dumps(summary) + "\n")
region = "us-east-1"
stream = "sonarqube-" + os.environ["GITHUB_RUN_ID"] + "-" + os.environ["GITHUB_RUN_ATTEMPT"]

def aws(*args):
    result = subprocess.run(["aws", "--region", region, *args], capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError("AWS reporting operation failed")

# Attempt both destinations independently. No individual findings are published.
delivery_failed = False
try:
    aws("logs", "create-log-stream", "--log-group-name", "/project-3/pipeline/scans",
        "--log-stream-name", stream)
    events = [{"timestamp": int(time.time() * 1000), "message": json.dumps(summary)}]
    aws("logs", "put-log-events", "--log-group-name", "/project-3/pipeline/scans",
        "--log-stream-name", stream, "--log-events", json.dumps(events))
except Exception:
    delivery_failed = True
    print("CloudWatch summary delivery failed.")
if failed or summary.get("issue_count", 0) or summary.get("quality_status") not in ("OK", "NONE"):
    try:
        aws("sns", "publish", "--topic-arn",
            "arn:aws:sns:us-east-1:YOUR_ACCOUNT_ID:project-3-secure-cicd-pipeline-scan-findings",
            "--subject", "Lab 3 SonarQube scan summary", "--message", json.dumps(summary))
    except Exception:
        delivery_failed = True
        print("SNS summary delivery failed.")
raise SystemExit(1 if failed or delivery_failed else 0)
```


## `packer/github-runner/github-runner.pkr.hcl`

Recorded at transcript line 38058.


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
  # Final image check: AWS program files contain no credentials and must be
  # executable by the unprivileged workflow account, with root-only writes.
  provisioner "shell" {
    inline = [
      "set -eu",
      "test -d /usr/local/aws-cli",
      "chown -R root:root /usr/local/aws-cli",
      "chmod -R a+rX,u+w,go-w /usr/local/aws-cli",
      "echo 'Checking AWS CLI access as actions-runner'",
      "runuser -u actions-runner -- /bin/bash -c 'test -x /usr/local/bin/aws && /usr/local/bin/aws --version'",
    ]
    execute_command = "sudo -E bash '{{ .Path }}'"
  }

}
```


## `packer/github-runner/scripts/install-runner.sh`

Recorded at transcript line 38754.


```bash
#!/usr/bin/env bash
set -Eeuo pipefail
umask 027

: "${GITHUB_RUNNER_VERSION:?GITHUB_RUNNER_VERSION is required}"
: "${GITLEAKS_VERSION:?GITLEAKS_VERSION is required}"
: "${SONAR_SCANNER_VERSION:?SONAR_SCANNER_VERSION is required}"
: "${DEPENDENCY_CHECK_VERSION:?DEPENDENCY_CHECK_VERSION is required}"
: "${ZAP_VERSION:?ZAP_VERSION is required}"
: "${TERRAFORM_VERSION:?TERRAFORM_VERSION is required}"
: "${AWS_CLI_VERSION:?AWS_CLI_VERSION is required}"
: "${JAVA_PACKAGE:?JAVA_PACKAGE is required}"

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get upgrade -y
apt-get install -y --no-install-recommends \
  ca-certificates curl unzip tar gzip xz-utils jq git gnupg dirmngr wget \
  "${JAVA_PACKAGE}" \
  libicu74 libkrb5-3 zlib1g libssl3 libcurl4 liblttng-ust1 \
  libunwind8 libnuma1 libsecret-1-0 libgtk-3-0 libdbus-glib-1-2 \
  libx11-xcb1 libasound2t64 fonts-liberation ufw snapd

install -d -m 0755 /opt/project-3/tools /opt/actions-runner /usr/local/bin

if ! id actions-runner >/dev/null 2>&1; then
  useradd --system --create-home --home-dir /home/actions-runner \
    --shell /usr/sbin/nologin actions-runner
fi
chown -R actions-runner:actions-runner /home/actions-runner /opt/actions-runner

workdir="$(mktemp -d)"
gpg_home="$(mktemp -d)"
chmod 0700 "$gpg_home"
export GNUPGHOME="$gpg_home"

cleanup() {
  rm -rf "$workdir" "$gpg_home"
}
trap cleanup EXIT
cd "$workdir"

download() {
  printf 'Downloading %s\n' "$1"
  curl --fail --location --retry 3 --silent --show-error \
    "$1" --output "$2"
}

import_and_check_key() {
  local key_id="$1"
  local expected_fingerprint="$2"
  local actual_fingerprint

  gpg --batch --keyserver hkps://keyserver.ubuntu.com --recv-keys "$key_id"
  actual_fingerprint="$(
    gpg --batch --with-colons --fingerprint "$key_id" |
      awk -F: '$1 == "fpr" { print $10; exit }'
  )"

  if [[ "$actual_fingerprint" != "$expected_fingerprint" ]]; then
    echo "Unexpected signing-key fingerprint for $key_id" >&2
    exit 1
  fi
}

verify_sha256() {
  local expected="$1"
  local file="$2"
  printf '%s  %s\n' "$expected" "$file" | sha256sum --check --status
}

# Ensure the Ubuntu 24.04 SSM Agent is installed and running.
if ! snap list amazon-ssm-agent >/dev/null 2>&1; then
  snap install amazon-ssm-agent --classic
fi
snap start amazon-ssm-agent

# GitHub Actions runner. Verify against the digest published in GitHub's
# release API; stop if a valid SHA-256 digest is unavailable.
runner_archive="actions-runner-linux-x64-${GITHUB_RUNNER_VERSION}.tar.gz"
runner_api="https://api.github.com/repos/actions/runner/releases/tags/v${GITHUB_RUNNER_VERSION}"
runner_digest="$(
  curl --fail --location --retry 3 --silent --show-error "$runner_api" |
    jq -r --arg name "$runner_archive" \
      '.assets[] | select(.name == $name) | .digest // empty'
)"
runner_digest="${runner_digest#sha256:}"

if [[ ! "$runner_digest" =~ ^[[:xdigit:]]{64}$ ]]; then
  echo "GitHub release did not provide a valid SHA-256 digest for $runner_archive" >&2
  exit 1
fi

download \
  "https://github.com/actions/runner/releases/download/v${GITHUB_RUNNER_VERSION}/${runner_archive}" \
  "$runner_archive"
verify_sha256 "$runner_digest" "$runner_archive"
tar -xzf "$runner_archive" -C /opt/actions-runner
/opt/actions-runner/bin/installdependencies.sh
chown -R actions-runner:actions-runner /opt/actions-runner

# Gitleaks. Verify the archive against the release checksum manifest.
gitleaks_archive="gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz"
gitleaks_checksums="gitleaks_${GITLEAKS_VERSION}_checksums.txt"
gitleaks_base="https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}"

download "${gitleaks_base}/${gitleaks_archive}" "$gitleaks_archive"
download "${gitleaks_base}/${gitleaks_checksums}" "$gitleaks_checksums"

grep -E "[[:space:]]${gitleaks_archive//./\\.}$" \
  "$gitleaks_checksums" > gitleaks-check.txt
test -s gitleaks-check.txt
sha256sum --check gitleaks-check.txt

tar -xzf "$gitleaks_archive" gitleaks
install -o root -g root -m 0755 gitleaks /usr/local/bin/gitleaks

# SonarScanner CLI. Verify the pinned SHA-256 for version 8.1.0.6389.
sonar_zip="sonar-scanner-cli-${SONAR_SCANNER_VERSION}-linux-x64.zip"
sonar_url="https://binaries.sonarsource.com/Distribution/sonar-scanner-cli/${sonar_zip}"
sonar_expected="bb8f709f9cb73352f8d1260a3b3c506c0f41146754bc630762c126d795499d0b"

if [[ "$SONAR_SCANNER_VERSION" != "8.1.0.6389" ]]; then
  echo "Update and review the SonarScanner checksum before changing its pinned version." >&2
  exit 1
fi

download "$sonar_url" "$sonar_zip"
verify_sha256 "$sonar_expected" "$sonar_zip"
unzip -q "$sonar_zip" -d /opt/project-3/tools
ln -sfn \
  "/opt/project-3/tools/sonar-scanner-${SONAR_SCANNER_VERSION}-linux-x64/bin/sonar-scanner" \
  /usr/local/bin/sonar-scanner

# Install the Node.js runtime required by Dependency-Check's npm audit analyzer.
# Verify the archive using the matching official Node.js checksum manifest.
node_version="22.23.4"
node_archive="node-v${node_version}-linux-x64.tar.xz"
download "https://nodejs.org/dist/v${node_version}/${node_archive}" "$node_archive"
download "https://nodejs.org/dist/v${node_version}/SHASUMS256.txt" node-SHASUMS256.txt
grep -F "  ${node_archive}" node-SHASUMS256.txt > node-check.txt
test -s node-check.txt
sha256sum --check node-check.txt
install -d -m 0755 "/opt/node-v${node_version}"
tar -xJf "$node_archive" --strip-components=1 -C "/opt/node-v${node_version}"
chown -R root:root "/opt/node-v${node_version}"
chmod -R a+rX,u+w,go-w "/opt/node-v${node_version}"
ln -sfn "/opt/node-v${node_version}/bin/node" /usr/local/bin/node
ln -sfn "/opt/node-v${node_version}/bin/npm" /usr/local/bin/npm
runuser -u actions-runner -- /usr/local/bin/node --version
runuser -u actions-runner -- /usr/local/bin/npm --version

# OWASP Dependency-Check. Verify its release signature.
dependency_check_zip="dependency-check-${DEPENDENCY_CHECK_VERSION}-release.zip"
dependency_check_url="https://github.com/dependency-check/DependencyCheck/releases/download/v${DEPENDENCY_CHECK_VERSION}"

download "${dependency_check_url}/${dependency_check_zip}" "$dependency_check_zip"
download "${dependency_check_url}/${dependency_check_zip}.asc" "${dependency_check_zip}.asc"

import_and_check_key \
  "259A55407DD6C00299E6607EFFDE55BE73A2D1ED" \
  "259A55407DD6C00299E6607EFFDE55BE73A2D1ED"
gpg --batch --verify "${dependency_check_zip}.asc" "$dependency_check_zip"

unzip -q "$dependency_check_zip" -d /opt/project-3/tools
ln -sfn /opt/project-3/tools/dependency-check/bin/dependency-check.sh \
  /usr/local/bin/dependency-check

# OWASP ZAP. Verify against the SHA-256 published for this release.
zap_archive="ZAP_${ZAP_VERSION}_Linux.tar.gz"
download \
  "https://github.com/zaproxy/zaproxy/releases/download/v${ZAP_VERSION}/${zap_archive}" \
  "$zap_archive"

if [[ "$ZAP_VERSION" == "2.17.0" ]]; then
  verify_sha256 \
    "efe799aaa3627db683b43f00c9c210aea0b75c00cc8f0a0f0434d12bb3ddde5a" \
    "$zap_archive"
else
  echo "Add and review the official SHA-256 for ZAP ${ZAP_VERSION} before building." >&2
  exit 1
fi

tar -xzf "$zap_archive" -C /opt/project-3/tools
ln -sfn "/opt/project-3/tools/ZAP_${ZAP_VERSION}/zap.sh" \
  /usr/local/bin/zap.sh

# Terraform. Verify HashiCorp's signed checksum manifest and the archive.
terraform_zip="terraform_${TERRAFORM_VERSION}_linux_amd64.zip"
terraform_base="https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}"

download "${terraform_base}/${terraform_zip}" "$terraform_zip"
download \
  "${terraform_base}/terraform_${TERRAFORM_VERSION}_SHA256SUMS" \
  terraform_SHA256SUMS
download \
  "${terraform_base}/terraform_${TERRAFORM_VERSION}_SHA256SUMS.sig" \
  terraform_SHA256SUMS.sig

import_and_check_key \
  "72D7468F" \
  "C874011F0AB405110D02105534365D9472D7468F"
gpg --batch --verify terraform_SHA256SUMS.sig terraform_SHA256SUMS

grep -E "[[:space:]]${terraform_zip//./\\.}$" terraform_SHA256SUMS |
  sha256sum --check

unzip -q "$terraform_zip" -d "$workdir"
install -o root -g root -m 0755 "$workdir/terraform" \
  /usr/local/bin/terraform

# AWS CLI v2. Verify its release signature and signing-key fingerprint.
awscli_zip="awscli-exe-linux-x86_64-${AWS_CLI_VERSION}.zip"
download "https://awscli.amazonaws.com/${awscli_zip}" "$awscli_zip"
download "https://awscli.amazonaws.com/${awscli_zip}.sig" "${awscli_zip}.sig"

import_and_check_key \
  "A6310ACC4672475C" \
  "FB5DB77FD5C118B80511ADA8A6310ACC4672475C"
gpg --batch --verify "${awscli_zip}.sig" "$awscli_zip"

unzip -q "$awscli_zip" -d "$workdir"
"$workdir/aws/install" --update

# CloudWatch Agent. Verify AWS's detached signature and key fingerprint.
cloudwatch_deb="amazon-cloudwatch-agent.deb"
download \
  https://amazoncloudwatch-agent.s3.amazonaws.com/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb \
  "$cloudwatch_deb"
download \
  https://amazoncloudwatch-agent.s3.amazonaws.com/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb.sig \
  "${cloudwatch_deb}.sig"
download \
  https://amazoncloudwatch-agent.s3.amazonaws.com/assets/amazon-cloudwatch-agent.gpg \
  amazon-cloudwatch-agent.gpg
gpg --batch --import amazon-cloudwatch-agent.gpg

cloudwatch_fingerprint="$(
  gpg --batch --with-colons --fingerprint 3B789C72 |
    awk -F: '$1 == "fpr" { print $10; exit }'
)"
if [[ "$cloudwatch_fingerprint" != "937616F3450B7D806CBD9725D58167303B789C72" ]]; then
  echo "Unexpected CloudWatch Agent signing-key fingerprint" >&2
  exit 1
fi

gpg --batch --verify "${cloudwatch_deb}.sig" "$cloudwatch_deb"
dpkg -i "$cloudwatch_deb"

# Bake CloudWatch log collection config. A systemd unit applies it after
# launch, when the deployed instance has its own IAM role and identity.
install -d -m 0755 /opt/aws/amazon-cloudwatch-agent/etc
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<'JSON'
{
  "agent": {
    "metrics_collection_interval": 60,
    "run_as_user": "root"
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/syslog",
            "log_group_name": "/project-3/github-runner",
            "log_stream_name": "{instance_id}/syslog",
            "retention_in_days": 14
          },
          {
            "file_path": "/var/log/auth.log",
            "log_group_name": "/project-3/github-runner",
            "log_stream_name": "{instance_id}/auth",
            "retention_in_days": 14
          },
          {
            "file_path": "/opt/actions-runner/_diag/Runner_*.log",
            "log_group_name": "/project-3/github-runner",
            "log_stream_name": "{instance_id}/runner",
            "retention_in_days": 14
          }
        ]
      }
    }
  }
}
JSON
chmod 0644 /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json

cat > /usr/local/sbin/project-3-start-cloudwatch-agent <<'SCRIPT'
#!/usr/bin/env bash
set -Eeuo pipefail
exec /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config -m ec2 \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json \
  -s
SCRIPT
chmod 0755 /usr/local/sbin/project-3-start-cloudwatch-agent

cat > /etc/systemd/system/project-3-cloudwatch-agent.service <<'UNIT'
[Unit]
Description=Start CloudWatch Agent with the instance runtime identity
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/project-3-start-cloudwatch-agent
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
UNIT
systemctl enable project-3-cloudwatch-agent.service

# Host firewall: no unsolicited inbound connections; outbound access remains
# available for GitHub, SSM, CloudWatch, and scanner update services.
ufw --force default deny incoming
ufw --force default allow outgoing
ufw --force enable

# Keep tool installations root-owned and remove package cache.
chown -R root:root /opt/project-3/tools
chmod -R go-w /opt/project-3/tools
chown -R actions-runner:actions-runner /home/actions-runner /opt/actions-runner
apt-get clean
rm -rf /var/lib/apt/lists/*

echo "Runner tools, SSM Agent, and CloudWatch setup completed. GitHub registration is deferred until instance launch."
```


## `scripts/report-dependency-check.py`

Recorded at transcript line 39588.


```python
#!/usr/bin/env python3
"""Write a concise Dependency-Check summary and publish it to AWS."""
import collections
import datetime
import json
import os
from pathlib import Path
import subprocess
import time

out = Path(os.environ["REPORT_DIR"])
out.mkdir(parents=True, exist_ok=True)
summary = {"tool": "OWASP Dependency-Check", "project": "juice-shop",
           "version": "20.3.0", "status": "execution_failed",
           "run": os.environ["RUN_URL"],
           "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat()}
commit = out / "source-commit.txt"
if commit.exists():
    summary["source_commit"] = commit.read_text().strip()
failed = False
try:
    if os.environ["SCAN_OUTCOME"] != "success":
        raise RuntimeError("Scanner failed")
    report = json.loads((out / "dependency-check-report.json").read_text())
    dependencies = report["dependencies"]
    if not dependencies:
        raise RuntimeError("Scan returned no dependencies")
    counts = collections.Counter()
    vulnerable = 0
    count = 0
    for dependency in dependencies:
        entries = dependency.get("vulnerabilities") or []
        if entries:
            vulnerable += 1
        for entry in entries:
            count += 1
            counts[str(entry.get("severity") or "UNKNOWN").upper()] += 1
    summary.update(status="completed_limited_coverage", coverage="packaged Node.js dependencies; no top-level lockfile; npm audit unavailable; false negatives possible", dependencies=len(dependencies),
                   vulnerable_dependencies=vulnerable,
                   vulnerability_occurrences=count, severities=dict(counts))
except Exception as error:
    failed = True
    summary["error_category"] = type(error).__name__
    print("Dependency-Check execution or report parsing failed.")

(out / "summary.json").write_text(json.dumps(summary, indent=2))
with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as step_summary:
    step_summary.write("### Dependency-Check result\n\n" + json.dumps(summary) + "\n")

def aws(*args):
    result = subprocess.run(["aws", "--region", "us-east-1", *args],
                            stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
    if result.returncode:
        raise RuntimeError("AWS reporting call failed")

delivery_failed = False
try:
    group = "/project-3/pipeline/scans"
    stream = "dependency-check-" + os.environ["GITHUB_RUN_ID"] + "-" + os.environ["GITHUB_RUN_ATTEMPT"]
    aws("logs", "create-log-stream", "--log-group-name", group, "--log-stream-name", stream)
    events = [{"timestamp": int(time.time() * 1000), "message": json.dumps(summary)}]
    aws("logs", "put-log-events", "--log-group-name", group,
        "--log-stream-name", stream, "--log-events", json.dumps(events))
except Exception:
    delivery_failed = True
    print("CloudWatch summary delivery failed.")
if failed or summary.get("vulnerability_occurrences", 0):
    try:
        aws("sns", "publish", "--topic-arn",
            "arn:aws:sns:us-east-1:YOUR_ACCOUNT_ID:project-3-secure-cicd-pipeline-scan-findings",
            "--subject", "Lab 3 Dependency-Check scan summary", "--message", json.dumps(summary))
    except Exception:
        delivery_failed = True
        print("SNS summary delivery failed.")
raise SystemExit(1 if failed or delivery_failed else 0)
```


## `scripts/report-zap.py`

Recorded at transcript line 41332.


```python
#!/usr/bin/env python3
"""Publish aggregate ZAP results without embedding request or response data."""
import collections
import datetime
import json
import os
from pathlib import Path
import subprocess
import time

out = Path(os.environ["REPORT_DIR"])
out.mkdir(parents=True, exist_ok=True)
summary = {
    "tool": "OWASP ZAP", "project": "juice-shop",
    "status": "execution_failed",
    "coverage": "unauthenticated traditional spider and bounded active scan; coverage is limited",
    "run": os.environ["RUN_URL"],
    "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat(),
}
failed = False
try:
    if os.environ["SCAN_OUTCOME"] != "success":
        raise RuntimeError("ZAP execution failed")
    report = json.loads((out / "zap-report.json").read_text())
    sites = report["site"]
    if not sites:
        raise RuntimeError("ZAP reported no sites")
    severities = collections.Counter()
    alerts = 0
    for site in sites:
        for alert in site.get("alerts", []):
            risk = str(alert.get("riskcode", "unknown"))
            name = {"3": "HIGH", "2": "MEDIUM", "1": "LOW", "0": "INFORMATIONAL"}.get(risk, "UNKNOWN")
            severities[name] += 1
            alerts += 1
    summary.update(status="completed", alert_types=alerts, severities=dict(severities))
except Exception as error:
    failed = True
    summary["error_category"] = type(error).__name__
    print("ZAP execution or report parsing failed.")

(out / "summary.json").write_text(json.dumps(summary, indent=2))
with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as step_summary:
    step_summary.write("### ZAP DAST summary\n\n" + json.dumps(summary) + "\n")

def aws(*args):
    result = subprocess.run(["aws", "--region", "us-east-1", *args],
                            stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
    if result.returncode:
        raise RuntimeError("AWS reporting failed")

delivery_failed = False
try:
    group = "/project-3/pipeline/scans"
    stream = "zap-" + os.environ["GITHUB_RUN_ID"] + "-" + os.environ["GITHUB_RUN_ATTEMPT"]
    aws("logs", "create-log-stream", "--log-group-name", group, "--log-stream-name", stream)
    events = [{"timestamp": int(time.time() * 1000), "message": json.dumps(summary)}]
    aws("logs", "put-log-events", "--log-group-name", group, "--log-stream-name", stream,
        "--log-events", json.dumps(events))
except Exception:
    delivery_failed = True
    print("CloudWatch summary delivery failed.")

if failed or summary.get("alert_types", 0):
    try:
        aws("sns", "publish", "--topic-arn",
            "arn:aws:sns:us-east-1:YOUR_ACCOUNT_ID:project-3-secure-cicd-pipeline-scan-findings",
            "--subject", "Lab 3 ZAP scan summary", "--message", json.dumps(summary))
    except Exception:
        delivery_failed = True
        print("SNS summary delivery failed.")
raise SystemExit(1 if failed or delivery_failed else 0)
```


## `terraform/compute/iam.tf`

Recorded at transcript line 41465.


```hcl
locals {
  common_tags = {
    Project     = var.project_name
    Environment = "lab"
    ManagedBy   = "Terraform"
  }

  cw_log_arns = [
    for name in [
      "/project-3/juice-shop/syslog",
      "/project-3/juice-shop/auth",
      "/project-3/juice-shop/app",
      "/project-3/github-runner",
      "/project-3/pipeline/scans",
    ] :
    "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:${name}:*"
  ]
}

data "aws_iam_policy_document" "ec2_trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "juice_shop" {
  name               = "${var.project_name}-juice-shop"
  assume_role_policy = data.aws_iam_policy_document.ec2_trust.json
  tags               = local.common_tags
}

resource "aws_iam_role" "github_runner" {
  name               = "${var.project_name}-github-runner"
  assume_role_policy = data.aws_iam_policy_document.ec2_trust.json
  tags               = local.common_tags
}

resource "aws_iam_role_policy_attachment" "juice_shop_ssm" {
  role       = aws_iam_role.juice_shop.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "runner_ssm" {
  role       = aws_iam_role.github_runner.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "juice_shop_logs" {
  name = "cloudwatch-logs"
  role = aws_iam_role.juice_shop.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:DescribeLogStreams", "logs:PutLogEvents"]
        Resource = slice(local.cw_log_arns, 0, 3)
      },
      {
        Effect   = "Allow"
        Action   = ["cloudwatch:PutMetricData"]
        Resource = "*"
        Condition = {
          StringEquals = {
            "cloudwatch:namespace" = "Project3/JuiceShop"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "runner_runtime" {
  name = "scanner-runtime"
  role = aws_iam_role.github_runner.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:DescribeLogStreams", "logs:PutLogEvents"]
        Resource = slice(local.cw_log_arns, 3, 5)
      },
      {
        Effect   = "Allow"
        Action   = ["ec2:DescribeInstances"]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = var.aws_region
          }
        }
      },
      {
        Effect   = "Allow"
        Action   = ["kms:GenerateDataKey", "kms:Decrypt"]
        Resource = "arn:aws:kms:${var.aws_region}:${data.aws_caller_identity.current.account_id}:key/*"
        Condition = {
          StringEquals = {
            "kms:ViaService" = "sns.${var.aws_region}.amazonaws.com"
          }
          "ForAnyValue:StringEquals" = {
            "kms:ResourceAliases" = "alias/aws/sns"
          }
        }
      },
      {
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = data.terraform_remote_state.observability.outputs.scan_findings_topic_arn
      },
      {
        Effect   = "Allow"
        Action   = ["ssm:GetParameter", "ssm:DeleteParameter"]
        Resource = "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter${var.runner_registration_token_parameter}"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "juice_shop" {
  name = "${var.project_name}-juice-shop"
  role = aws_iam_role.juice_shop.name
}

resource "aws_iam_instance_profile" "github_runner" {
  name = "${var.project_name}-github-runner"
  role = aws_iam_role.github_runner.name
}
```


## `.github/workflows/sonarqube-analysis.yml`

Recorded at transcript line 41976.


```yaml
name: Juice Shop SonarQube analysis
on:
  push:
    branches: [master]
    paths:
      - ".github/workflows/sonarqube-analysis.yml"
      - "packer/juice-shop/**"
  workflow_call:
  workflow_dispatch:
permissions:
  contents: read
concurrency:
  group: juice-shop-sonarqube-analysis
  cancel-in-progress: false
jobs:
  analyze:
    if: github.ref == 'refs/heads/master'
    environment: sonarqube-scan
    runs-on: [self-hosted, linux, x64, project-3-scanner]
    timeout-minutes: 30
    steps:
      - name: Check out reporting automation
        uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683
        with:
          path: automation
          persist-credentials: false
      - name: Check out matching Juice Shop release source
        uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683
        with:
          repository: juice-shop/juice-shop
          ref: v20.3.0
          path: juice-shop
          fetch-depth: 0
          persist-credentials: false
      - name: Verify source version and scanner
        working-directory: juice-shop
        shell: bash
        run: |
          set -Eeuo pipefail
          python3 -c 'import json; assert json.load(open("package.json"))["version"] == "20.3.0"'
          sonar-scanner --version
          mkdir -p "$RUNNER_TEMP/sonar-receipt"
          git rev-parse HEAD > "$RUNNER_TEMP/sonar-receipt/source-commit.txt"
      - name: Submit application analysis
        id: scan
        working-directory: juice-shop
        shell: bash
        env:
          SONAR_TOKEN: ${{ secrets.SONAR_TOKEN }}
          SONAR_HOST_URL: ${{ vars.SONAR_HOST_URL }}
        run: |
          set -Eeuo pipefail
          test -n "$SONAR_TOKEN"
          test -n "$SONAR_HOST_URL"
          sonar-scanner \
            -Dsonar.projectKey=project-3-juice-shop \
            -Dsonar.projectVersion=20.3.0 \
            -Dsonar.sources=. \
            -Dsonar.exclusions='**/node_modules/**,**/dist/**,**/coverage/**,**/.scannerwork/**' \
            -Dsonar.sourceEncoding=UTF-8 \
            -Dsonar.qualitygate.wait=false
          cp .scannerwork/report-task.txt "$RUNNER_TEMP/sonar-receipt/report-task.txt"
          echo "Analysis submitted. Server processing and findings must be reviewed in SonarQube." >> "$GITHUB_STEP_SUMMARY"
          echo "Quality gate results do not block deployment in this lab." >> "$GITHUB_STEP_SUMMARY"
      - name: Export findings and publish aggregate summaries
        if: always()
        env:
          SONAR_HOST_URL: ${{ vars.SONAR_HOST_URL }}
          SONAR_REPORT_TOKEN: ${{ secrets.SONAR_REPORT_TOKEN }}
          SCAN_OUTCOME: ${{ steps.scan.outcome }}
          REPORT_DIR: ${{ runner.temp }}/sonar-receipt
          RUN_URL: ${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}
        run: python3 automation/scripts/report-sonarqube.py
      - name: Upload scan results and receipt
        if: always()
        uses: actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02
        with:
          name: sonarqube-results
          path: ${{ runner.temp }}/sonar-receipt/
          retention-days: 7
          if-no-files-found: ignore
      - name: Clean scanner workspace
        if: always()
        shell: bash
        run: |
          rm -rf -- "$GITHUB_WORKSPACE/juice-shop/.scannerwork" "$RUNNER_TEMP/sonar-receipt"
```


## `.github/workflows/dependency-check.yml`

Recorded at transcript line 42028.


```yaml
name: Juice Shop Dependency-Check
on:
  push:
    branches: [master]
    paths:
      - ".github/workflows/dependency-check.yml"
      - "scripts/report-dependency-check.py"
      - "packer/juice-shop/**"
  workflow_call:
  workflow_dispatch:
permissions:
  contents: read
concurrency:
  group: juice-shop-dependency-check
  cancel-in-progress: false
jobs:
  scan:
    if: github.ref == 'refs/heads/master'
    environment: dependency-check
    runs-on: [self-hosted, linux, x64, project-3-scanner]
    timeout-minutes: 180
    steps:
      - name: Check out reporting automation
        uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683
        with:
          path: automation
          persist-credentials: false
      - name: Check out Juice Shop source
        uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683
        with:
          repository: juice-shop/juice-shop
          ref: v20.3.0
          path: juice-shop
          persist-credentials: false
      - name: Verify source and tools
        working-directory: juice-shop
        shell: bash
        run: |
          set -Eeuo pipefail
          python3 -c 'import json; assert json.load(open("package.json"))["version"] == "20.3.0"'
          echo "Source release has no top-level lockfile; scanning the packaged release artifact."
          npm --version
          dependency-check --version
          mkdir -p "$RUNNER_TEMP/dependency-check-report"
          git rev-parse HEAD > "$RUNNER_TEMP/dependency-check-report/source-commit.txt"
      - name: Scan application dependencies
        id: scan
        shell: bash
        env:
          NVD_API_KEY: ${{ secrets.NVD_API_KEY }}
        run: |
          set -Eeuo pipefail
          umask 077
          report="$RUNNER_TEMP/dependency-check-report"
          mkdir -p "$report" "$HOME/.cache/project-3/dependency-check"
          archive="$RUNNER_TEMP/juice-shop-20.3.0.tgz"
          unpack="$RUNNER_TEMP/juice-shop-artifact"
          rm -rf -- "$unpack"
          mkdir -p "$unpack"
          curl --fail --location --retry 3 --silent --show-error \
            "https://github.com/juice-shop/juice-shop/releases/download/v20.3.0/juice-shop-20.3.0_node22_linux_x64.tgz" \
            --output "$archive"
          printf '%s  %s\n' '6148dcce8fe7d990a86bf8457a0e9a07821c127d498c76da1a3bc7dba12a77e5' "$archive" | sha256sum --check --strict
          tar -xzf "$archive" -C "$unpack"
          package_json="$(find "$unpack" -maxdepth 3 -type f -name package.json -print -quit)"
          test -n "$package_json"
          app_dir="$(dirname "$package_json")"
          test -d "$app_dir/node_modules"
          python3 -c 'import json,sys; assert json.load(open(sys.argv[1]))["version"] == "20.3.0"' "$package_json"
          properties="$(mktemp "$RUNNER_TEMP/odc.XXXXXXXX")"
          diagnostic_log="$(mktemp "$RUNNER_TEMP/odc-log.XXXXXXXX")"
          trap 'rm -f "$properties" "$diagnostic_log"' EXIT
          if [ -z "$NVD_API_KEY" ]; then
            echo "NVD_API_KEY is missing from the dependency-check environment; configure it before retrying." >&2
            exit 1
          fi
          [[ "$NVD_API_KEY" =~ ^[a-zA-Z0-9-]+$ ]] || { echo "Invalid NVD key format" >&2; exit 1; }
          printf 'nvd.api.key=%s\n' "$NVD_API_KEY" > "$properties"
          unset NVD_API_KEY
          printf 'ecosystem.skip.cpeanalyzer=[]\n' >> "$properties"
          set +e
          dependency-check --log "$diagnostic_log" \
            --disableNodeAudit --disableYarnAudit --disablePnpmAudit \
            --project "Project 3 Juice Shop 20.3.0" \
            --scan "$app_dir" \
            --data "$HOME/.cache/project-3/dependency-check" \
            --propertyfile "$properties" \
            --format JSON --format HTML \
            --out "$report"
          scan_status=$?
          set -e
          if [ "$scan_status" -ne 0 ]; then
            echo "Dependency-Check failed with exit status $scan_status; exception class and analyzer frames:"
            python3 -c 'import re,sys; text=open(sys.argv[1], errors="replace").read(); pats=[r"(?<![A-Za-z0-9_$])(?:[a-zA-Z_$][\w$]*\.)+[A-Za-z_$][\w$]*(?:Exception|Error)\b", r"(?<=at )org\.owasp\.dependencycheck\.[\w.$]+"]; matches=[]; [matches.append(m) for pat in pats for m in re.findall(pat,text) if m not in matches]; print("\n".join(matches[:40]) if matches else "No exception class or Dependency-Check frame recorded.")' "$diagnostic_log"
            exit "$scan_status"
          fi
          test -s "$report/dependency-check-report.json"
      - name: Export and publish summary
        if: always()
        env:
          SCAN_OUTCOME: ${{ steps.scan.outcome }}
          REPORT_DIR: ${{ runner.temp }}/dependency-check-report
          RUN_URL: ${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}
        run: python3 automation/scripts/report-dependency-check.py
      - name: Upload Dependency-Check reports
        if: always()
        uses: actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02
        with:
          name: dependency-check-results
          path: ${{ runner.temp }}/dependency-check-report/
          if-no-files-found: ignore
          retention-days: 7
      - name: Clean report workspace
        if: always()
        run: rm -rf -- "$RUNNER_TEMP/dependency-check-report" "$RUNNER_TEMP/juice-shop-artifact" "$RUNNER_TEMP/juice-shop-20.3.0.tgz"
```


## `.github/workflows/zap-dast.yml`

Recorded at transcript line 42080.


```yaml
name: Juice Shop ZAP DAST
on:
  workflow_call:
  workflow_dispatch:
permissions:
  contents: read
concurrency:
  group: juice-shop-zap-dast
  cancel-in-progress: false
jobs:
  scan:
    if: github.ref == 'refs/heads/master'
    runs-on: [self-hosted, linux, x64, project-3-scanner]
    timeout-minutes: 45
    steps:
      - name: Check out trusted configuration
        uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683
        with:
          persist-credentials: false
      - name: Scan the approved Juice Shop target
        id: scan
        shell: bash
        run: |
          set -Eeuo pipefail
          umask 077
          report="$RUNNER_TEMP/project-3-zap-report"
          mkdir -p "$report"
          # Fail closed unless exactly one running, tagged lab instance is found.
          instances="$(aws ec2 describe-instances --region us-east-1 \
            --filters "Name=tag:Project,Values=project-3-secure-cicd-pipeline" \
                      "Name=tag:Name,Values=project-3-secure-cicd-pipeline-juice-shop" \
                      "Name=instance-state-name,Values=running" \
            --query 'Reservations[].Instances[].{ip:PrivateIpAddress,vpc:VpcId}' --output json)"
          ip="$(printf '%s' "$instances" | python3 -c 'import ipaddress,json,sys; x=json.load(sys.stdin); assert len(x)==1; ip=ipaddress.ip_address(x[0]["ip"]); assert ip in ipaddress.ip_network("10.20.0.0/16"); print(ip)')"
          target="http://$ip:3000"
          target_regex="${ip//./[.]}"
          curl --fail --silent --show-error --connect-timeout 5 --max-time 15 "$target/" -o /dev/null
          cat > "$report/plan.yaml" <<EOF
          env:
            contexts:
              - name: juice-shop
                urls:
                  - "$target"
                includePaths:
                  - 'http://$target_regex:3000/.*'
            parameters:
              failOnError: true
              failOnWarning: false
              progressToStdout: true
          jobs:
            - type: spider
              parameters:
                context: juice-shop
                url: "$target"
                maxDuration: 2
            - type: passiveScan-wait
              parameters:
                maxDuration: 2
            - type: activeScan
              parameters:
                context: juice-shop
                url: "$target"
                maxScanDurationInMins: 10
            - type: passiveScan-wait
              parameters:
                maxDuration: 2
            - type: report
              parameters:
                template: traditional-json
                reportDir: "$report"
                reportFile: zap-report.json
            - type: report
              parameters:
                template: traditional-html
                reportDir: "$report"
                reportFile: zap-report.html
          EOF
          set +e
          zap.sh -cmd -autorun "$report/plan.yaml"
          status=$?
          set -e
          if [ "$status" -ne 0 ]; then
            echo "ZAP returned status $status; check the automation output."
            exit "$status"
          fi
          test -s "$report/zap-report.json"
          test -s "$report/zap-report.html"
      - name: Publish scan summary
        if: always()
        env:
          SCAN_OUTCOME: ${{ steps.scan.outcome }}
          REPORT_DIR: ${{ runner.temp }}/project-3-zap-report
          RUN_URL: ${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}
        run: python3 scripts/report-zap.py
      - name: Upload ZAP reports
        if: always()
        uses: actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02
        with:
          name: zap-dast-results
          path: ${{ runner.temp }}/project-3-zap-report/
          if-no-files-found: ignore
          retention-days: 7
      - name: Clean scan workspace
        if: always()
        run: rm -rf -- "$RUNNER_TEMP/project-3-zap-report"
```


## `.github/workflows/terraform-deploy.yml`

Recorded at transcript line 42132.


```yaml
name: Terraform deployment

on:
  push:
    branches: [master]
    paths:
      - "terraform/**"
      - "iam/terraform-github-oidc/apply-permissions.json"
      - ".github/workflows/terraform-*.yml"
      - "docs/terraform-layering-rationale.md"
      - "LAB-3-SOURCE-OF-TRUTH.md"
  workflow_call:
  workflow_dispatch:

permissions:
  contents: read
  id-token: write

concurrency:
  group: project-3-terraform-deployment
  cancel-in-progress: false

jobs:
  network:
    uses: ./.github/workflows/terraform-layer.yml
    with:
      root: network
      juice_shop_allowed_cidrs: ${{ vars.JUICE_SHOP_ALLOWED_CIDRS || '[]' }}
      state_bucket: ${{ vars.TF_STATE_BUCKET }}
      aws_region: us-east-1
      plan_role_arn: ${{ vars.AWS_TERRAFORM_PLAN_ROLE_ARN }}
      apply_role_arn: ${{ vars.AWS_TERRAFORM_APPLY_ROLE_ARN }}

  database:
    needs: network
    uses: ./.github/workflows/terraform-layer.yml
    with:
      root: database
      state_bucket: ${{ vars.TF_STATE_BUCKET }}
      aws_region: us-east-1
      plan_role_arn: ${{ vars.AWS_TERRAFORM_PLAN_ROLE_ARN }}
      apply_role_arn: ${{ vars.AWS_TERRAFORM_APPLY_ROLE_ARN }}

  observability:
    needs: network
    uses: ./.github/workflows/terraform-layer.yml
    with:
      root: observability
      notification_email: ${{ vars.TF_NOTIFICATION_EMAIL || '' }}
      state_bucket: ${{ vars.TF_STATE_BUCKET }}
      aws_region: us-east-1
      plan_role_arn: ${{ vars.AWS_TERRAFORM_PLAN_ROLE_ARN }}
      apply_role_arn: ${{ vars.AWS_TERRAFORM_APPLY_ROLE_ARN }}

  compute:
    needs: [network, observability]
    uses: ./.github/workflows/terraform-layer.yml
    secrets:
      RUNNER_GITHUB_APP_ID: ${{ secrets.RUNNER_GITHUB_APP_ID }}
      RUNNER_GITHUB_APP_PRIVATE_KEY: ${{ secrets.RUNNER_GITHUB_APP_PRIVATE_KEY }}
    with:
      root: compute
      state_bucket: ${{ vars.TF_STATE_BUCKET }}
      aws_region: us-east-1
      plan_role_arn: ${{ vars.AWS_TERRAFORM_PLAN_ROLE_ARN }}
      apply_role_arn: ${{ vars.AWS_TERRAFORM_APPLY_ROLE_ARN }}

  sonarqube:
    needs: [network, database, observability]
    uses: ./.github/workflows/terraform-layer.yml
    with:
      root: sonarqube
      state_bucket: ${{ vars.TF_STATE_BUCKET }}
      aws_region: us-east-1
      plan_role_arn: ${{ vars.AWS_TERRAFORM_PLAN_ROLE_ARN }}
      apply_role_arn: ${{ vars.AWS_TERRAFORM_APPLY_ROLE_ARN }}
```


## `.github/workflows/secure-pipeline.yml`

Recorded at transcript line 42164.


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


## `scripts/report-gitleaks.py`

Recorded at transcript line 42188.


```python
#!/usr/bin/env python3
"""Publish counts only; never publish secret values or matching lines."""
import datetime
import json
import os
from pathlib import Path
import subprocess
import time

summary = {"tool": "Gitleaks", "status": "execution_failed",
           "run": os.environ["RUN_URL"],
           "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat()}
failed = False
try:
    if os.environ["SCAN_OUTCOME"] != "success":
        raise RuntimeError("Scan did not complete")
    report = json.loads(Path("reports/gitleaks.json").read_text())
    if not isinstance(report, list):
        raise ValueError("Unexpected report format")
    summary.update(status="completed", findings=len(report))
except Exception as error:
    failed = True
    summary["error_category"] = type(error).__name__
Path("reports").mkdir(exist_ok=True)
Path("reports/summary.json").write_text(json.dumps(summary, indent=2))
with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as file:
    file.write("### Gitleaks summary\n\n" + json.dumps(summary) + "\n")

def aws(*args):
    subprocess.run(["aws", "--region", "us-east-1", *args],
                   stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, check=True)

delivery_failed = False
try:
    group = "/project-3/pipeline/scans"
    stream = "gitleaks-" + os.environ["GITHUB_RUN_ID"] + "-" + os.environ["GITHUB_RUN_ATTEMPT"]
    aws("logs", "create-log-stream", "--log-group-name", group, "--log-stream-name", stream)
    aws("logs", "put-log-events", "--log-group-name", group, "--log-stream-name", stream,
        "--log-events", json.dumps([{"timestamp": int(time.time() * 1000), "message": json.dumps(summary)}]))
except Exception:
    delivery_failed = True
    print("CloudWatch summary delivery failed.")
if failed or summary.get("findings", 0):
    try:
        aws("sns", "publish", "--topic-arn",
            "arn:aws:sns:us-east-1:YOUR_ACCOUNT_ID:project-3-secure-cicd-pipeline-scan-findings",
            "--subject", "Lab 3 Gitleaks scan summary", "--message", json.dumps(summary))
    except Exception:
        delivery_failed = True
        print("SNS summary delivery failed.")
raise SystemExit(1 if failed or delivery_failed else 0)
```


## `.github/workflows/gitleaks-aws.yml`

Recorded at transcript line 42238.


```yaml
name: Gitleaks secrets scan on AWS

on:
  push:
    branches:
      - master
  workflow_call:
  workflow_dispatch:

permissions:
  contents: read

concurrency:
  group: gitleaks-aws-${{ github.ref }}
  cancel-in-progress: true

jobs:
  gitleaks:
    if: github.ref == 'refs/heads/master'
    runs-on:
      - self-hosted
      - linux
      - x64
      - project-3-scanner
    timeout-minutes: 15
    steps:
      - name: Check out full Git history
        uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683
        with:
          fetch-depth: 0
          persist-credentials: false

      - name: Scan Git history with Gitleaks
        id: scan
        shell: bash
        run: |
          set -Eeuo pipefail
          gitleaks version

          mkdir -p reports
          raw_report="$RUNNER_TEMP/gitleaks-raw.json"
          trap 'rm -f "$raw_report"' EXIT

          gitleaks git . \
            --no-banner \
            --redact=100 \
            --report-format json \
            --report-path "$raw_report" \
            --exit-code 0

          test -s "$raw_report"
          jq 'map({
            Description,
            StartLine,
            EndLine,
            StartColumn,
            EndColumn,
            File,
            SymlinkFile,
            Commit,
            Entropy,
            RuleID,
            Tags
          })' "$raw_report" > reports/gitleaks.json

      - name: Publish Gitleaks summary
        if: always()
        env:
          SCAN_OUTCOME: ${{ steps.scan.outcome }}
          RUN_URL: ${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}
        run: python3 scripts/report-gitleaks.py

      - name: Upload sanitized Gitleaks report
        if: always()
        uses: actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02
        with:
          name: gitleaks-aws-report
          path: |
            reports/gitleaks.json
            reports/summary.json
          if-no-files-found: ignore
          retention-days: 7
```

# Project 3 — Step-by-step lab walkthrough

I recorded this lab in the order I worked through it: workstation setup, Packer, the initial Terraform deployment, the move to GitHub Actions, separate scanner tests, and finally the combined pipeline. I use the same command-led style as my [Project 2B walkthrough](https://github.com/DelaneKay/project-2b-isolated-juice-shop/blob/main/docs/walkthrough.md).

**Location:** Unless a command is explicitly marked otherwise, I run it in my WSL workstation as `devsecops`, from `~/projects/project-3-secure-cicd-pipeline`. An `aws ssm send-command` command runs in WSL and asks SSM to execute its quoted payload on EC2. The EC2 host cannot see my WSL checkout.

**Record boundaries:** The available chat includes many terminal screenshots and command outputs, but several earlier assistant replies containing the original installation and file-creation commands are absent. I do not claim that those missing commands were preserved. Command blocks using current resource lookups, placeholders, or commands expanded from the repository are **adapted reproduction commands**, not verbatim historical terminal records. The historical commands explicitly identified below are preserved from the chat. UI work has UI steps rather than invented shell equivalents.

**Reproduction prerequisite:** This walkthrough starts with the completed, version-controlled configuration. It does not reproduce every `nano` paste used to author those files. The source files in the repository supply those reviewed definitions. A literal replay from an empty AWS account still needs the missing operator-profile/OIDC bootstrap details identified at the end of this document.

## 1. Confirm the working directory and identity

I checked the checkout in WSL. This command sequence was shown in the chat:

```bash
cd ~/projects/project-3-secure-cicd-pipeline
git status --short --branch
git remote -v
```

The first attempt reported that the directory was not a Git repository. After authenticating GitHub CLI and cloning the existing repository, the working tree showed `master...origin/master`. I inspected the existing directory before cloning because it already contained the Session Manager installer; I did not overwrite it.

I verified the AWS IAM-user identity using the named profile:

```bash
aws sts get-caller-identity \
  --profile mds-devsecops-lab \
  --query Arn \
  --output text
```

The recorded caller ended with `:user/mds-devsecops-lab`. Some screenshots also showed a Linux root shell or an AWS root ARN; these are different identities. I returned to the normal WSL user and the intended AWS profile before continuing.

## 2. Verify the installed tools

The chat records Packer `1.16.2` and Session Manager plugin `1.2.896.0` installed successfully. The full original installation commands are not present, so the commands below are verification commands rather than a claimed installation transcript:

```bash
packer version
session-manager-plugin --version
```

I used Ubuntu 24.04 LTS. This exact AMI lookup appeared in the chat:

```bash
aws ssm get-parameter \
  --name /aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id \
  --query 'Parameter.Value' \
  --output text \
  --profile mds-devsecops-lab \
  --region us-east-1
```

It returned the historical base image `ami-0d6dd9e8265d48906`. I verified its Canonical image metadata before using it; future builds must check the currently selected image.

## 3. Create the Packer builder role

This role-creation block was included in the chat. It runs once, with an IAM-user profile authorized to perform these operations. It does not create EC2:

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

The final recorded output was `project-3-packer-builder-role`. If a create operation has already succeeded, I inspect the existing resource before retrying; these commands are not an idempotent provisioning script.

## 4. Separate the local Packer identity from the builder identity

When Packer failed to find credentials, I changed the design to use a dedicated operator role. I checked its caller identity:

```bash
aws sts get-caller-identity --profile project-3-packer --query Arn --output text
```

The recorded result was an assumed-role ARN ending in `project-3-packer-operator-role/project-3-packer-build`. The original complete operator trust/policy and credential-process setup commands are not retained in the visible chat. [The bootstrap guide](packer-builder-iam-bootstrap.md) describes the intended setup, but I do not present it as a complete verbatim command record.

## 5. Build and record the images, deploy the lab, and test the separate workflows

The following execution sections use the completed repository files. Where IDs or versions are supplied as shell variables instead of literal values from an old run, I label that as an adapted reproduction sequence. Historical ID values in troubleshooting identify the old run only.

## Execution sequence using the repository

I started with separate workflows, verified each one, and only then connected them. This section records that order. Resource IDs changed during rebuilds, so I use current lookup commands and clearly marked placeholders rather than reusing terminated instance IDs. Some setup was performed in GitHub and SonarQube screens; those steps do not have a shell command in this chat.

### 5.1 Open the project and authenticate

I ran these commands as my normal WSL user:

```bash
cd ~/projects
gh auth login --hostname github.com --git-protocol https
gh auth setup-git

# Clone once, into a directory that does not already contain the project.
gh repo clone DelaneKay/project-3-secure-cicd-pipeline
cd ~/projects/project-3-secure-cicd-pipeline
git status --short --branch
git remote -v

aws sts get-caller-identity --profile mds-devsecops-lab --query Arn --output text
aws sts get-caller-identity --profile project-3-packer --query Arn --output text
packer version
terraform version
session-manager-plugin --version
```

If the directory already existed, I inspected it before cloning. I did not delete an existing project to work around a clone error. Authentication renewal used my configured AWS CLI login profile; credentials and root-recovery operations are not part of the deployment runbook.

### 5.2 Create and inspect the working folders

```bash
mkdir -p packer/juice-shop/scripts
mkdir -p packer/sonarqube/scripts
mkdir -p packer/github-runner/scripts
mkdir -p terraform/network terraform/database terraform/compute
mkdir -p terraform/sonarqube terraform/observability

find packer -maxdepth 3 -type f | sort
find terraform -maxdepth 2 -type f \
  ! -name 'terraform.tfstate*' ! -name '*.tfplan' | sort

nano packer/juice-shop/scripts/install-juice-shop.sh
nano packer/sonarqube/scripts/install-sonarqube.sh
nano packer/github-runner/scripts/install-runner.sh
```

I used the version-controlled files in those locations for the script contents. In nano I saved with Ctrl+O, Enter, and exited with Ctrl+X. When Git opened a pager showing END, I pressed q.

### 5.3 Bootstrap IAM and build networking

I followed the full role-creation command block in [Packer IAM bootstrap](docs/packer-builder-iam-bootstrap.md). I then checked the builder profile:

```bash
aws iam get-instance-profile \
  --profile mds-devsecops-lab \
  --instance-profile-name project-3-packer-builder-profile \
  --query 'InstanceProfile.Roles[].RoleName' --output text

aws iam list-attached-role-policies \
  --profile mds-devsecops-lab \
  --role-name project-3-packer-builder-role --output table

aws ec2 describe-subnets \
  --profile mds-devsecops-lab --region us-east-1 \
  --query 'Subnets[].{Subnet:SubnetId,Vpc:VpcId,PublicIP:MapPublicIpOnLaunch}' \
  --output table

aws ec2 describe-security-groups \
  --profile mds-devsecops-lab --region us-east-1 \
  --group-ids sg-REPLACE \
  --query 'SecurityGroups[].{Ingress:IpPermissions,Egress:IpPermissionsEgress}' \
  --output json
```

The temporary builder security group had no inbound rules and outbound TCP 80/443. Initially I used bootstrap networking; later Terraform managed a dedicated builder group. I selected a subnet with a working outbound path, not a private subnet without the required connectivity.

### 5.4 Build all three images

I supplied current values rather than relying on old defaults in templates:

```bash
export AWS_PROFILE=project-3-packer
export PKR_VAR_aws_region=us-east-1
export PKR_VAR_source_ami_id=ami-REPLACE_WITH_VERIFIED_UBUNTU_2404_IMAGE
export PKR_VAR_subnet_id=subnet-REPLACE
export PKR_VAR_security_group_id=sg-REPLACE

bash -n packer/juice-shop/scripts/install-juice-shop.sh
packer init packer/juice-shop
packer validate packer/juice-shop
packer build packer/juice-shop

# Load the version pins I reviewed in the repository.
set -a
source packer/sonarqube/version.env
set +a
export PKR_VAR_sonarqube_version="$SONARQUBE_VERSION"
export PKR_VAR_java_package="$JAVA_PACKAGE"
bash -n packer/sonarqube/scripts/install-sonarqube.sh
bash -n packer/sonarqube/scripts/start-sonarqube.sh
packer init packer/sonarqube
packer validate packer/sonarqube
packer build packer/sonarqube

set -a
source packer/github-runner/versions.env
set +a
export PKR_VAR_github_runner_version="$GITHUB_RUNNER_VERSION"
export PKR_VAR_gitleaks_version="$GITLEAKS_VERSION"
export PKR_VAR_sonar_scanner_version="$SONAR_SCANNER_VERSION"
export PKR_VAR_dependency_check_version="$DEPENDENCY_CHECK_VERSION"
export PKR_VAR_zap_version="$ZAP_VERSION"
export PKR_VAR_terraform_version="$TERRAFORM_VERSION"
export PKR_VAR_aws_cli_version="$AWS_CLI_VERSION"
export PKR_VAR_java_package="$JAVA_PACKAGE"
bash -n packer/github-runner/scripts/install-runner.sh
packer init packer/github-runner
packer validate packer/github-runner
packer build packer/github-runner
```

After each successful build I checked the returned AMI and its backing snapshot:

```bash
aws ec2 describe-images \
  --profile mds-devsecops-lab --region us-east-1 \
  --image-ids ami-REPLACE_WITH_BUILD_OUTPUT \
  --query 'Images[].{AMI:ImageId,State:State,Snapshots:BlockDeviceMappings[].Ebs.SnapshotId}' \
  --output table

# Example for SonarQube; use its actual returned AMI and snapshot IDs.
cat > packer/sonarqube/ami-id.txt <<'EOF'
AMI_ID=ami-REPLACE
SNAPSHOT_ID=snap-REPLACE
AWS_REGION=us-east-1
EOF
cat packer/sonarqube/ami-id.txt
```

I recorded the other images in their corresponding ami-id.txt files. These records are evidence; Terraform's AMI data sources select available images by project and image tags.

### 6. Bootstrap state and update the scoped Terraform policy

```bash
AWS_PROFILE=mds-devsecops-lab AWS_REGION=us-east-1 \
  ./scripts/bootstrap-terraform-state.sh

git pull --ff-only

aws iam put-role-policy \
  --role-name project-3-terraform-apply-role \
  --policy-name project-3-terraform-apply-policy \
  --policy-document file://iam/terraform-github-oidc/apply-permissions.json \
  --profile mds-devsecops-lab

aws iam get-role-policy \
  --role-name project-3-terraform-apply-role \
  --policy-name project-3-terraform-apply-policy \
  --profile mds-devsecops-lab \
  --query 'PolicyDocument.Statement[].Sid' --output text
```

I configured the OIDC provider, repository variables, GitHub App credentials and protected apply environment using the setup document. Policy files contain account-specific values and must be reviewed before use in another account.

### 7. Deploy the prerequisite lab

```bash
gh workflow run terraform-deploy.yml --ref master
gh run list --workflow terraform-deploy.yml --limit 5
```

I opened that run in GitHub, reviewed its saved plans and approved each pending apply. I did not run a second deployment while the first was awaiting approval.

```bash
gh api repos/DelaneKay/project-3-secure-cicd-pipeline/actions/runners \
  --jq '.runners[] | {name,status,busy,labels:[.labels[].name]}'
```

For SSM diagnostics I used this two-command pattern. I copied the numeric instance ID from the current inventory and used the command ID returned by send-command:

```bash
aws ssm send-command \
  --profile mds-devsecops-lab --region us-east-1 \
  --instance-ids i-REPLACE \
  --document-name AWS-RunShellScript \
  --parameters 'commands=["systemctl is-active juice-shop.service","curl --fail --silent --output /dev/null --write-out \"HTTP %{http_code}\\n\" http://127.0.0.1:3000/"]' \
  --query 'Command.CommandId' --output text

aws ssm get-command-invocation \
  --profile mds-devsecops-lab --region us-east-1 \
  --command-id REPLACE_WITH_RETURNED_COMMAND_ID \
  --instance-id i-REPLACE \
  --query '{Status:Status,Output:StandardOutputContent,Errors:StandardErrorContent}' \
  --output json
```

I used the SonarQube health endpoint `http://127.0.0.1:9000/api/system/status` on its instance and checked for status UP. These are read-only checks.

### 8. Separate workflows first — Test each scanner separately

I configured the SonarQube project and protected secrets before running its analysis. I confirmed the SNS subscription through its email link. Tokens were entered through protected secret fields, never committed.

I started each workflow separately, waited for its result, and checked its reports before moving on:

```bash
gh workflow run gitleaks-aws.yml --ref master
gh run list --workflow gitleaks-aws.yml --limit 3

gh workflow run sonarqube-analysis.yml --ref master
gh run list --workflow sonarqube-analysis.yml --limit 3

gh workflow run dependency-check.yml --ref master
gh run list --workflow dependency-check.yml --limit 3

gh workflow run zap-dast.yml --ref master
gh run list --workflow zap-dast.yml --limit 3
```

For any one of those runs I used the returned numeric run ID:

```bash
gh run watch RUN_ID --exit-status
gh run view RUN_ID
gh run view RUN_ID --log-failed
gh run download RUN_ID --dir ~/project-3-artifact-review/RUN_ID
```

RUN_ID is a placeholder. I replaced it with the ID from run list. Where WSL could not reach GitHub, I used the Actions page to inspect logs and download the report.

Before ZAP I checked that the runner account could execute it:

```bash
aws ssm send-command \
  --profile mds-devsecops-lab --region us-east-1 \
  --instance-ids i-REPLACE_WITH_CURRENT_RUNNER_ID \
  --document-name AWS-RunShellScript \
  --parameters 'commands=["runuser -u actions-runner -- /usr/local/bin/zap.sh -version"]' \
  --query 'Command.CommandId' --output text
```

The ZAP workflow now discovers the running tagged Juice Shop instance itself, verifies the address is in the lab CIDR, and fails if it cannot identify exactly one target.

### 9. Verify CloudWatch and SNS

```bash
aws logs describe-log-streams \
  --profile mds-devsecops-lab --region us-east-1 \
  --log-group-name /project-3/pipeline/scans --output json

aws sns list-subscriptions-by-topic \
  --profile mds-devsecops-lab --region us-east-1 \
  --topic-arn arn:aws:sns:us-east-1:273517699789:project-3-secure-cicd-pipeline-scan-findings \
  --output json
```

I checked the email as well as the job result. An execution-failed email from an earlier run is not the successful scan's findings notification; I compared its run link.

### 10. Combined workflow after separate tests — Commit the work and then run the combined pipeline

I used feature branches and reviewed changes before publishing:

```bash
git switch -c feat/REPLACE_WITH_CHANGE_NAME
git status --short
git add PATH_TO_REVIEWED_FILE
git diff --cached --check
git --no-pager diff --cached --stat
git commit -m "Describe the completed change"
git push -u origin HEAD
gh pr create --base master --title "Describe the change" --body "Explain the change and validation"
```

After the individual workflows worked, I made them reusable and connected them in secure-pipeline.yml. I kept their separate entry points.

Once that change was merged, I ran the combined workflow:

```bash
gh workflow run secure-pipeline.yml --ref master
gh run list --workflow secure-pipeline.yml --limit 3
gh run watch RUN_ID --exit-status
```

I reviewed and approved the pending Terraform plans in the same run. ZAP ran after deployment. The first successful combined run was 41846334576:

```bash
gh run view 41846334576
gh run download 41846334576 --dir ~/project-3-artifact-review/41846334576
```

### 11. Teardown through the protected workflow

When I am ready to remove the lab, I optionally create the manual RDS backup first, verify it, then use the destroy workflow:

```bash
# Optional backup demonstration; the snapshot is billable until deleted.
aws rds create-db-snapshot \
  --profile mds-devsecops-lab --region us-east-1 \
  --db-instance-identifier project-3-sonarqube \
  --db-snapshot-identifier project-3-manual-lab-backup

aws rds wait db-snapshot-available \
  --profile mds-devsecops-lab --region us-east-1 \
  --db-snapshot-identifier project-3-manual-lab-backup

gh workflow run terraform-destroy.yml --ref master -f confirmation=DESTROY
gh run list --workflow terraform-destroy.yml --limit 3
```

I approve the reviewed destroy plans. After the lab is gone and I no longer need that manual backup, I remove that specific snapshot:

```bash
aws rds delete-db-snapshot \
  --profile mds-devsecops-lab --region us-east-1 \
  --db-snapshot-identifier project-3-manual-lab-backup
```

AMIs, backing snapshots, bootstrap IAM and the versioned state bucket require the separate final cleanup described above. I inventory them before deleting anything and do not use a broad account-wide delete command.


## Challenges I faced and how I solved them

I kept this section separate from the setup walkthrough. These commands are diagnostics I used or adapted from the investigation; they are not all required for every deployment. Replace placeholder IDs with the current resources, and avoid putting passwords, tokens or raw secret findings in logs.

### 1. Packer could not find valid AWS credentials

**What happened:** My IAM user could call AWS CLI, but Packer failed with `No valid credential sources found`. An AWS CLI login session did not automatically give Packer the credentials it expected.

**How I investigated:** I checked the caller identity under each profile instead of assuming that an interactive login and a machine process were using the same identity.

```bash
aws sts get-caller-identity --profile mds-devsecops-lab --query Arn --output text
aws sts get-caller-identity --profile project-3-packer --query Arn --output text
```

**How I resolved it:** I configured the Packer profile to assume a dedicated operator role using short-lived source credentials. I kept that operator role separate from the SSM role attached to the temporary builder. The intended caller for a build is the assumed operator role, not the root user. The setup is documented in [Packer IAM bootstrap](docs/packer-builder-iam-bootstrap.md).

### 2. GitHub Actions could not assume the Terraform role

**What happened:** The Terraform plan job failed with `Not authorized to perform sts:AssumeRoleWithWebIdentity`.

**How I investigated:** I compared the role's OIDC trust conditions with the repository and environment that triggered the workflow. GitHub's token subject for this repository used immutable owner and repository identifiers, while the trust policy initially did not match it.

```bash
aws iam get-role \
  --profile mds-devsecops-lab \
  --role-name project-3-terraform-plan-role \
  --query 'Role.AssumeRolePolicyDocument' \
  --output json

aws iam get-role \
  --profile mds-devsecops-lab \
  --role-name project-3-terraform-apply-role \
  --query 'Role.AssumeRolePolicyDocument' \
  --output json
```

**How I resolved it:** I corrected the exact repository, branch and environment subject claims in the relevant trust policies. The plan role and apply role remain separate, and the apply role is tied to the protected environment. I documented the policy setup in [GitHub Actions Terraform setup](docs/github-actions-terraform-setup.md).

### 3. Terraform could not launch EC2 after I rebuilt the VPC

**What happened:** `ec2:RunInstances` returned an authorization error for the network interface, subnet and security group even though the role could create the instance in an earlier deployment.

**How I investigated:** I used AWS's authorization details and compared the current VPC and subnet IDs with the conditions in the deployed role policy.

```bash
aws ec2 describe-vpcs \
  --profile mds-devsecops-lab --region us-east-1 \
  --filters 'Name=tag:Project,Values=project-3-secure-cicd-pipeline' \
  --query 'Vpcs[].{VpcId:VpcId,Cidr:CidrBlock}' --output table

aws ec2 describe-subnets \
  --profile mds-devsecops-lab --region us-east-1 \
  --filters 'Name=vpc-id,Values=vpc-REPLACE' \
  --query 'Subnets[].{SubnetId:SubnetId,VpcId:VpcId,Cidr:CidrBlock}' --output table

aws iam get-role-policy \
  --profile mds-devsecops-lab \
  --role-name project-3-terraform-apply-role \
  --policy-name project-3-terraform-apply-policy \
  --query "PolicyDocument.Statement[?Sid=='LaunchInterfacesInLabVpc']" \
  --output json
```

**How I resolved it:** Destroying and recreating the network gave me new IDs, but the bootstrap apply-role policy still referred to the old ones. I updated the policy with the current lab VPC and subnets, applied it with the IAM-user profile, and generated a fresh Terraform plan. This remains a manual dependency after network recreation; it is an improvement to automate rather than a solved long-term design.

I also encountered the IAM inline-policy size limit. I checked the policy's size excluding formatting whitespace and reduced duplication instead of attaching broad administrator permissions.

### 4. A Terraform plan became stale and a database resource already existed

**What happened:** One apply reported `Saved plan is stale` after state changed, and a later run reported that the RDS subnet group already existed. I also encountered a state-lock conflict while operations overlapped.

**How I investigated:** I checked the active GitHub Actions runs, the AWS resource and the Terraform state relationship. A resource existing in AWS does not by itself mean it is recorded in the correct Terraform state.

```bash
gh run list --workflow terraform-deploy.yml --limit 5

aws rds describe-db-subnet-groups \
  --profile mds-devsecops-lab --region us-east-1 \
  --db-subnet-group-name project-3-sonarqube-subnets \
  --query 'DBSubnetGroups[].{Name:DBSubnetGroupName,VpcId:VpcId,Status:SubnetGroupStatus}' \
  --output json

aws rds describe-db-instances \
  --profile mds-devsecops-lab --region us-east-1 \
  --db-instance-identifier project-3-sonarqube \
  --query 'DBInstances[].{Identifier:DBInstanceIdentifier,Status:DBInstanceStatus}' \
  --output table
```

**How I resolved it:** I stopped overlapping operations and used the repository's database import workflow to reconcile the existing resources with their intended state. I then generated a **new plan** and reviewed it before applying. I did not disable locking to bypass the conflict. If a lock appears abandoned, I first verify that no operation is running before considering a carefully scoped unlock.

### 5. SonarQube started, but its HTTP service was unavailable

**What happened:** EC2 was running and registered with SSM, but the SonarQube health endpoint returned HTTP 000. The process could be active or activating while the web application was not yet ready.

**How I investigated:** I identified the current instance and used SSM to inspect service state and a bounded set of journal entries. A read-only diagnostic is different from configuring a deployed host.

```bash
aws ssm send-command \
  --profile mds-devsecops-lab --region us-east-1 \
  --instance-ids i-REPLACE_WITH_CURRENT_SONARQUBE_ID \
  --document-name AWS-RunShellScript \
  --parameters 'commands=["systemctl is-active sonarqube.service || true","journalctl -u sonarqube.service -n 40 --no-pager"]' \
  --query 'Command.CommandId' --output text
```

I retrieved the result with `aws ssm get-command-invocation`, using the returned command ID and the same instance ID. I avoided sharing database credentials or printing secret values.

**How I resolved it:** The SonarQube service account could not execute the AWS CLI installed under root-owned directories. I fixed the file permissions and executable-path checks **in the Packer image build**, built a new AMI, and replaced the instance through Terraform. I then confirmed SonarQube's health endpoint returned `UP`. I later applied the same lesson to the scanner runner when its AWS CLI permissions prevented CloudWatch/SNS reporting.

### 6. The scanner ran out of memory

**What happened:** A SonarQube analysis failed on the original `t3.small` scanner. The operating system's out-of-memory killer terminated a process used by the Actions runner.

**How I investigated:** I used SSM for read-only memory and kernel-log checks:

```bash
aws ssm send-command \
  --profile mds-devsecops-lab --region us-east-1 \
  --instance-ids i-REPLACE_WITH_CURRENT_RUNNER_ID \
  --document-name AWS-RunShellScript \
  --parameters 'commands=["free -m","journalctl -k --no-pager | grep -i -E \"out of memory|oom-kill|killed process\" | tail -20"]' \
  --query 'Command.CommandId' --output text
```

**How I resolved it:** I changed the runner size to `c7i-flex.large` and used Terraform to replace the instance, preserving the immutable approach. I then confirmed the new runner registered online and reran the analysis successfully. A larger runner costs more, so I account for its running time in the lab budget.

### 7. Dependency-Check failed before producing a trustworthy result

**What happened:** First the NVD update failed because the API key was empty. After correcting that, the scan wrote reports but exited with analyzer initialization errors. Treating those partial reports as a clean scan would have been misleading.

**How I investigated:** I opened the failed GitHub Actions job, checked the scanner output and added a diagnostic that printed exception class names without exposing the NVD key. The diagnostic showed `StringIndexOutOfBoundsException` in `Settings.getArray`.

```bash
gh run list --workflow dependency-check.yml --limit 5

# Replace with the numeric ID of the run being investigated.
gh run view RUN_ID --log-failed
```

**How I resolved it:** I stored the NVD key in the appropriate GitHub environment secret and changed the CPE skip setting from an empty string to an empty array:

```properties
ecosystem.skip.cpeanalyzer=[]
```

A subsequent run showed that the Node Package and CPE analyzers finished. I still label its results **limited coverage** because this release artifact has no top-level lockfile and the npm/Yarn/pnpm audit analyzers are disabled.

### 8. Gitleaks reported a public-key fingerprint

**What happened:** Gitleaks flagged a historical line as a possible generic API key. A finding is a lead for investigation, not proof that the value is a live credential.

**How I investigated:** I checked the variable name at the reported commit and line without printing the value:

```bash
git show '9d2406ca349dfe9ad1aac51dedc80129a819c226:packer/sonarqube/scripts/install-sonarqube.sh' \
  | sed -n '9p' \
  | cut -d= -f1
```

The line was the AWS CLI signing-key fingerprint, which is a public verification value. I handled it as a narrowly scoped false positive and reran the scan. If a finding were a real secret, I would revoke or rotate it and investigate exposure rather than simply suppressing it.

### 9. GitHub CLI timed out, but the workflow had run

**What happened:** WSL sometimes returned `TLS handshake timeout` while contacting GitHub. That was a connectivity failure from my terminal, not evidence that the GitHub Actions job itself had failed.

**How I resolved it:** I checked the run directly under **GitHub → Actions** in the browser, opened the relevant job and reviewed its logs and artifacts. Once connectivity was restored I could use `gh run list` and `gh run view` again.

### What these challenges taught me

I learned to verify the identity making a request, read the exact AWS authorization decision, check Terraform state before retrying, and separate instance status from application readiness. Most importantly, I corrected image and workflow definitions and retested them instead of silently changing the running application host.




## Command coverage and missing historical material

I compared this record with the available Project 3 chat, rather than describing every paragraph as a verbatim transcript.

| Part of the lab | What is preserved here |
| --- | --- |
| Workstation and repository checks | Commands and observed Git/profile failures |
| Tool installation | Recorded versions; original complete install commands are missing |
| Packer builder IAM | The complete role/profile block from the chat |
| Packer operator IAM and credential-process | Verified assumed-role result; original complete configuration commands are missing |
| Image builds | Repository templates, adapted commands for all three images, plus historical build examples |
| Initial manual Terraform stage | Recorded early validation/plan/apply progression; the original complete file creation pastes are missing |
| GitHub Terraform stage | Repository workflows, invocation commands, approval steps and state/IAM troubleshooting |
| GitHub OIDC and GitHub App bootstrap | Configuration described in setup guide; original full bootstrap/UI sequence is not retained |
| SonarQube setup | Recorded UI actions and analysis/reporting credentials; exact setup workflow filename must be verified in the repository before invocation |
| Separate scanners | The workflow invocation/check pattern, SSM diagnostics and recorded results |
| Combined workflow | Invocation, first successful run ID and report download |
| Evidence and teardown | Report handling, destroy workflow and cleanup responsibilities |

This is a command-led working record, but the missing historical bootstrap material prevents me from honestly claiming it is a complete empty-account replay using only the visible chat. I will fill those gaps from the original exported conversation if it becomes available, rather than inventing commands and attributing them to the lab.

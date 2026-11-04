# Project 3 — Building a Secure CI/CD Pipeline on AWS

I built this lab to bring together application security, infrastructure as code and deployment automation in one working pipeline. My application is [OWASP Juice Shop](https://owasp.org/www-project-juice-shop/), an intentionally vulnerable web application. I use it as a safe lab target to see how security tools behave when they actually find issues.

The pipeline uses GitHub Actions, Packer and Terraform to deploy the lab on AWS, then combines secrets scanning, static analysis, dependency scanning and dynamic testing. CloudWatch records scan summaries, and SNS sends concise email notifications.

**This is a learning lab, not a production reference deployment.** Juice Shop is deliberately vulnerable. I restrict access to the lab, use test data, and scan only the application I own and have permission to test.

## What I built

![Pipeline and infrastructure flow](https://img.shields.io/badge/CI%2FCD-GitHub%20Actions-2088FF?logo=githubactions)

```mermaid
flowchart LR
    Dev["Developer<br/>Git + WSL"] --> GH["GitHub repository<br/>and Actions"]
    GH -->|"OIDC: plan and apply"| AWS["AWS infrastructure"]
    Packer["Packer<br/>builds 3 AMIs"] --> AWS

    subgraph Lab["AWS lab"]
      Runner["Self-hosted scanner<br/>GitHub Actions runner"]
      App["Juice Shop<br/>EC2 :3000"]
      Sonar["SonarQube<br/>private EC2 :9000"]
      DB[("RDS PostgreSQL<br/>:5432")]
      Secrets["Secrets Manager"]
      Logs["CloudWatch Logs"]
      SNS["SNS"]
      Runner -->|"SAST"| Sonar
      Runner -->|"ZAP DAST"| App
      Sonar --> DB
      Sonar --> Secrets
      Runner --> Logs
      Runner --> SNS
    end

    AWS --> Lab
    SNS --> Email["Email summary"]
```

The running lab consists of three EC2 instances—Juice Shop, SonarQube and a separate scanner runner—plus an RDS for PostgreSQL database. Packer uses temporary build instances to create images. GitHub hosts the Terraform runner; application security scans use my self-hosted EC2 runner.

I kept **separate workflows** for demonstrating and troubleshooting individual tools, and added one combined workflow to show the full sequence:

```text
Gitleaks + SonarQube + Dependency-Check
                ↓
        Terraform plan and approval
                ↓
     Terraform applies the saved plans
                ↓
       ZAP scans running Juice Shop
```

The three pre-deployment scans are independent jobs. Because this lab has one scanner runner, they are queued and run one at a time. The runner and SonarQube must already exist before this combined workflow starts; after a full teardown I bootstrap the lab infrastructure first.

Vulnerability and secret findings are **report-only** in this lab. A finding does not stop deployment. A scanner or reporting execution failure is different: it is reported as a failure rather than being presented as a clean scan, and can stop the combined workflow before deployment.

## Tools and why I used them

| Tool or service | What I used it for |
| --- | --- |
| GitHub Actions | Separate and combined workflows, reports and deployment approvals |
| Gitleaks | Scan repository history for potentially exposed secrets |
| SonarQube and SonarScanner | Static analysis and quality-profile checks on the Juice Shop source |
| OWASP Dependency-Check | Check packaged dependencies against vulnerability data |
| OWASP ZAP | Test the running application using an unauthenticated spider and bounded active scan |
| Packer | Build the Juice Shop, SonarQube and scanner-runner AMIs |
| Terraform | Create and destroy AWS infrastructure in separate layers |
| AWS IAM and GitHub OIDC | Give workflows and instances distinct, scoped identities |
| AWS Systems Manager | Manage instances without inbound SSH |
| RDS PostgreSQL and Secrets Manager | Persist SonarQube data and manage its database credentials |
| CloudWatch and SNS | Store aggregate scan summaries and send email notifications |

I did not add a container scanner, an Ansible admin node or a deployment-blocking SonarQube quality gate to this lab.

## Walkthrough

My detailed [step-by-step command walkthrough](docs/walkthrough.md) follows the Project 2B format: execution location, commands, observed results and challenges. It also identifies historical setup commands that are missing from the available chat, so readers can distinguish preserved commands from adapted reproduction examples.


### 1. Prepare my workstation and AWS identity

I worked in WSL and used the AWS CLI, Packer, Terraform, Git, GitHub CLI and the Session Manager plugin. I authenticated with my IAM user using short-lived credentials; I did not use the AWS root user for the lab.

From my project directory I checked the active identity and installed tools:

```bash
cd ~/projects/project-3-secure-cicd-pipeline

aws sts get-caller-identity \
  --profile mds-devsecops-lab \
  --region us-east-1

packer version
terraform version
aws --version
session-manager-plugin --version
gh auth status
```

Before building an AMI I checked that the **Packer operator role**, rather than the IAM user directly, was being used:

```bash
aws sts get-caller-identity \
  --profile project-3-packer \
  --query Arn \
  --output text
```

The expected result is an assumed-role ARN for `project-3-packer-operator-role`. My IAM user's short-lived session is the source for that role profile. I do not place long-lived AWS keys in GitHub or bake them into images.

### 2. Bootstrap Packer access

Packer needs AWS access before the Terraform lab infrastructure exists, so I prepared two separate identities:

- **Packer operator role:** used by the Packer process to make the required EC2 and SSM API calls.
- **Packer builder role and instance profile:** attached to the temporary build instance, with Systems Manager access.

I documented the role setup and cleanup in [Packer IAM bootstrap](docs/packer-builder-iam-bootstrap.md). The operator's `iam:PassRole` permission is limited to the builder role and EC2.

Packer connects to its temporary builder using its SSH communicator **through an SSM tunnel**. There is no public inbound port 22 or SSH key for deployed lab hosts. Builder networking still needs a working outbound path for package downloads and Systems Manager.

### 3. Bake the three AMIs

I used Ubuntu 24.04 LTS as the base and created one image per role:

1. **Juice Shop:** the Node.js application, non-root service, SSM and CloudWatch configuration.
2. **SonarQube:** SonarQube, Java, SSM and CloudWatch, with a baked startup service that obtains runtime database settings and credentials.
3. **Scanner runner:** GitHub Actions runner software, Gitleaks, SonarScanner, Dependency-Check, ZAP, AWS CLI and supporting tools.

I applied OS updates and role-specific host hardening while building the images. Security groups and IAM permissions are separate AWS controls managed by Terraform. I use IMDSv2 on the instances.

For example, I can look up the current Canonical Ubuntu 24.04 AMD64 base image with:

```bash
aws ssm get-parameter \
  --profile mds-devsecops-lab \
  --region us-east-1 \
  --name /aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id \
  --query 'Parameter.Value' \
  --output text
```

I initialize and validate a template before building it. The variables below are examples; the subnet and security group must belong to the same build VPC and must provide the required connectivity:

```bash
cd ~/projects/project-3-secure-cicd-pipeline

packer init packer/sonarqube

packer validate \
  -var 'source_ami_id=ami-REPLACE' \
  -var 'subnet_id=subnet-REPLACE' \
  -var 'security_group_id=sg-REPLACE' \
  -var 'sonarqube_version=26.10.0.133078' \
  -var 'java_package=openjdk-21-jdk' \
  packer/sonarqube

AWS_PROFILE=project-3-packer packer build \
  -var 'source_ami_id=ami-REPLACE' \
  -var 'subnet_id=subnet-REPLACE' \
  -var 'security_group_id=sg-REPLACE' \
  -var 'sonarqube_version=26.10.0.133078' \
  -var 'java_package=openjdk-21-jdk' \
  packer/sonarqube
```

The other image definitions are in [packer/juice-shop](packer/juice-shop/) and [packer/github-runner](packer/github-runner/); the runner's pinned tool versions are in [versions.env](packer/github-runner/versions.env). Packer builds create billable temporary resources and AMI backing snapshots, so I check the results and clean them up when finished.

My goal is immutable deployment: when baked software or configuration changes, I build a new AMI and replace the instance. **A successful image build alone does not prove that the deployed service is healthy**, so I verify runtime health separately.

### 4. Prepare Terraform state and GitHub access

I split infrastructure into five independent Terraform roots, each with its own state key and S3 native lock file:

| Root | Responsibility |
| --- | --- |
| [network](terraform/network/) | VPC, subnets, routing, endpoints and security groups |
| [database](terraform/database/) | Private RDS PostgreSQL |
| [observability](terraform/observability/) | CloudWatch and SNS resources |
| [compute](terraform/compute/) | Juice Shop and scanner-runner instances and roles |
| [sonarqube](terraform/sonarqube/) | Private SonarQube instance and role |

The state bucket has to exist before Terraform can use it as a backend. I bootstrap it once with my authenticated IAM-user profile:

```bash
cd ~/projects/project-3-secure-cicd-pipeline

AWS_PROFILE=mds-devsecops-lab AWS_REGION=us-east-1 \
  ./scripts/bootstrap-terraform-state.sh
```

I configured GitHub's AWS OIDC provider and separate plan/apply roles. The workflow obtains short-lived credentials; I do not store long-lived AWS access keys in GitHub. The apply job uses the protected `terraform-lab-apply` environment and waits for a reviewer.

The exact repository variables, secrets, role trust, runner registration and state configuration are documented in [GitHub Actions Terraform setup](docs/github-actions-terraform-setup.md). I also explain why I split the configuration in [Terraform layering rationale](docs/terraform-layering-rationale.md).

**Important lab limitation:** the apply-role policy includes specific VPC and subnet IDs. If I destroy and recreate the network, AWS gives it new IDs and I must review and update that scoped policy before instance launches can succeed. That manual step is a known improvement opportunity; it is not fully automated by the current implementation.

### 5. Deploy the infrastructure in layers

I use **Actions → Terraform deployment** to run the infrastructure workflow. It plans each layer and saves the plan for review. Apply jobs wait for approval in `terraform-lab-apply`; after approval, the workflow applies the saved plan.

The dependency order is:

```text
network
  ├── database ───────────┐
  └── observability ──────┼── SonarQube
           └──────────────┴── compute
```

Database and observability can run in parallel once networking is available. Compute waits for networking and observability; SonarQube waits for networking, the database and observability. Separate state files make each layer easier to review, but they also mean I must respect their dependencies during deployment and teardown.

I configured the runner to register at launch using a short-lived GitHub App registration token. The token is delivered through an SSM SecureString and removed after use. The EC2 instance is replaced when its AMI or the configured immutable runner sizing changes. It is a separate scanner host; this lab does **not** automatically create a fresh runner for every job.

At the time of the successful run, I used a `c7i-flex.large` scanner runner and a `c7i-flex.large` SonarQube instance. I increased the runner from `t3.small` after a SonarQube scan exhausted its memory. Instance types and prices should be reviewed for a new run.

### 6. Verify the deployed services

Terraform success tells me infrastructure operations completed; it does not prove that the application is ready. I verify running instances and SSM registration:

```bash
aws ec2 describe-instances \
  --profile mds-devsecops-lab \
  --region us-east-1 \
  --filters \
    'Name=tag:Project,Values=project-3-secure-cicd-pipeline' \
    'Name=instance-state-name,Values=running' \
  --query 'Reservations[].Instances[].{Name:Tags[?Key==`Name`]|[0].Value,Id:InstanceId,Type:InstanceType,PrivateIP:PrivateIpAddress}' \
  --output table

aws ssm describe-instance-information \
  --profile mds-devsecops-lab \
  --region us-east-1 \
  --query 'InstanceInformationList[].{Instance:InstanceId,Status:PingStatus}' \
  --output table
```

I also check that Juice Shop responds on port 3000, SonarQube reports `UP`, and the scanner runner appears online in GitHub. I use SSM for these read-only checks; I do not fix application configuration by logging into a running host. If an image needs a change, I update the Packer build and replace the instance.

The SonarQube launcher gets the database endpoint and secret reference at runtime and retrieves credentials from Secrets Manager using its instance role. The PostgreSQL database is private and is not baked into the image.

### 7. Configure SonarQube

Once SonarQube was healthy, I changed the initial admin password, configured the Juice Shop project and its quality profiles, and set up separate tokens for analysis and reporting. I store tokens in GitHub Actions secrets, never in the repository.

The scan workflow uses the `sonarqube-scan` environment, `SONAR_HOST_URL`, `SONAR_TOKEN` and `SONAR_REPORT_TOKEN`. The reporter account only needs the project access required for its reports. My scan uses the pinned Juice Shop 20.3.0 source; I must keep the source version aligned with the application image I deploy.

A quality-profile finding is reported to me. A quality-gate result is visible in SonarQube but does not block this intentionally vulnerable lab deployment.

### 8. Run the separate security workflows

I first tested each scanner independently so I could troubleshoot its configuration before combining the jobs.

| Workflow | What it scans | Evidence |
| --- | --- | --- |
| **Gitleaks secrets scan on AWS** | Repository Git history | Sanitized findings and summary; secret values are not included in notifications |
| **Juice Shop SonarQube analysis** | Juice Shop source code | SonarQube analysis and exported findings |
| **Juice Shop Dependency-Check** | The packaged Juice Shop dependencies | JSON and HTML reports and aggregate summary |
| **Juice Shop ZAP DAST** | The deployed Juice Shop over its private address | JSON and HTML ZAP reports and aggregate summary |

I keep scanner findings separate from scanner failures. For example, a successful Dependency-Check run may report vulnerable packages, while a failed NVD update must be recorded as an execution failure—not as zero vulnerabilities.

Dependency-Check uses an NVD API key stored as the `NVD_API_KEY` GitHub environment secret. Its current packaged scan has **limited coverage**: there is no top-level lockfile, npm/Yarn/pnpm audit analyzers are disabled, and false negatives are possible. The ZAP workflow uses an unauthenticated traditional spider and bounded active scan, so JavaScript-driven and authenticated areas are not fully covered.

### 9. Run the combined pipeline

With the lab infrastructure, scanner runner and SonarQube already available, I open **Actions → Combined secure CI-CD pipeline → Run workflow**, select `master`, and start the run.

The pipeline calls the same separate workflows:

1. Gitleaks scans repository history.
2. SonarQube analyzes the application source.
3. Dependency-Check analyzes the packaged dependencies.
4. Terraform creates reviewable plans. I inspect the plans and approve the pending apply jobs.
5. ZAP discovers the running tagged Juice Shop instance and tests that lab target.

The combined workflow is manually triggered in this implementation. Some individual workflows also have their own push triggers, so separate runs can occur independently. The pipeline currently uses one persistent self-hosted runner; untrusted pull-request code must not be given access to that runner and its AWS identity.

My first combined run completed successfully in GitHub Actions: [combined run 41846334576](https://github.com/DelaneKay/project-3-secure-cicd-pipeline/actions/runs/41846334576). The green result means the jobs completed, not that Juice Shop contains no vulnerabilities.

### 10. Review reports and notifications

Each scan uploads an Actions artifact. CloudWatch receives a concise summary; SNS sends an aggregate email when there are findings or a scan/reporting failure. I confirm the SNS email subscription before expecting messages.

In the successful combined run:

- **Gitleaks:** 0 findings in that run.
- **SonarQube:** 272 issues; the reported quality status was `OK`.
- **Dependency-Check:** 20 vulnerable dependencies and 66 vulnerability occurrences, with limited coverage.
- **ZAP:** 5 alert types—2 medium and 3 informational—with limited coverage.

These counts describe one run and are not a guarantee of complete coverage. An occurrence is not necessarily a distinct vulnerability, and results need review for false positives.

The original [Actions run](https://github.com/DelaneKay/project-3-secure-cicd-pipeline/actions/runs/41846334576) contains the temporary artifacts. Scan report archives and an explanation are prepared in [the evidence folder](docs/evidence/combined-run-41846334576/) when the corresponding evidence pull request is merged. Terraform saved plans are not published there because they can contain sensitive values.

### 11. Back up, destroy and verify

This is a lab, so I do not leave infrastructure running when I no longer need it. The network endpoints, EC2 instances, RDS database, storage, snapshots, logs and state bucket can incur charges.

If I want to demonstrate a backup, I create and verify a manual RDS snapshot **before** teardown. The current RDS configuration disables automatic backup retention and skips the final snapshot on destroy; a backup is not created automatically by Packer or Ansible. A manual snapshot continues to incur storage charges until I delete it.

I run **Actions → Terraform destroy**, type `DESTROY`, review the destroy plans, and approve the protected jobs. The workflow removes the Terraform-managed layers in reverse dependency order. Terraform destroy does **not** remove everything created outside those states.

My final cleanup includes:

- Any manual RDS snapshots, once they are no longer needed.
- Packer-created AMIs and their backing EBS snapshots, including older versions.
- The Packer operator and builder roles, policies and instance profile.
- Stale self-hosted runner registrations.
- All current and noncurrent objects in the versioned Terraform state bucket, then the bucket itself.
- Any other lab resources found during the final inventory.

I verify the AWS account and region before cleanup, and check AWS Billing/Cost Explorer as well as EC2, RDS, VPC endpoints, snapshots, CloudWatch and S3. Removing the lab resources does not retroactively remove charges already incurred.

## Trust boundaries

I documented each boundary by asking what crosses it and which control is responsible for limiting it.

| Boundary | What crosses it and how I restrict it |
| --- | --- |
| Developer workstation → GitHub | Code and workflow changes. I use GitHub authentication, review changes and scan repository history for secrets. |
| GitHub repository → Actions runner | Workflow and application code. Only trusted workflow code runs on the self-hosted scanner; it has its own identity and host. |
| GitHub Actions → AWS | Terraform API requests. GitHub OIDC exchanges short-lived credentials for scoped plan and apply roles, with a protected apply environment. |
| Scanner runner → SonarQube | Analysis and reporting requests. SonarQube is private, the security group allows the required path, and tokens are kept in GitHub secrets. |
| Scanner runner → Juice Shop | ZAP HTTP requests. The scan is limited to the lab target and its private application port. |
| Lab user → Juice Shop | Browser requests to an intentionally vulnerable application. I restrict the security group to approved lab sources and use test data. |
| SonarQube → RDS | PostgreSQL traffic. RDS is private and its security group permits the SonarQube security group on port 5432. |
| SonarQube → Secrets Manager | Database credential retrieval. The instance role can access the required secret; the image does not contain the password. |
| EC2 → Systems Manager | Management traffic using the instance role and SSM Agent. I do not expose inbound SSH. |
| Packer operator → AWS APIs → temporary builder | Image creation, packages and configuration. The operator and builder use separate roles, and temporary builders are removed after the build. |
| Terraform → state bucket | Infrastructure state and lock objects. State is kept in a private, encrypted, versioned bucket with separate keys and lock files. |
| Scan jobs and hosts → CloudWatch → SNS → email | Aggregate results and notifications. I avoid sending secret values and use a confirmed subscription. |

Security groups, IAM roles, GitHub environment protections and host controls each protect different parts of the path. A tag-based target lookup is useful for discovery, but tags alone are not an authorization boundary.

## What I learned

This lab took several iterations. A green Terraform apply did not mean SonarQube was ready: I traced its startup failure to AWS CLI permissions for the non-root service account, corrected the Packer image and replaced the instance. I also moved the scanner to a larger instance after an out-of-memory failure.

Dependency-Check initially failed because of a missing NVD key, then because an empty analyzer setting was parsed incorrectly. The corrected configuration let the analyzers finish, while the final report still records its coverage limitations. I also saw why saved plans become stale if state changes between planning and applying, and why an IAM policy tied to a particular VPC and subnets needs attention after rebuilding the network.

Those problems were useful: they showed me the difference between **infrastructure creation, service readiness, scanner execution and security findings**. Each needs its own verification.

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


## Command-by-command execution record

I started with separate workflows, verified each one, and only then connected them. This section records that order. Resource IDs changed during rebuilds, so I use current lookup commands and clearly marked placeholders rather than reusing terminated instance IDs. Some setup was performed in GitHub and SonarQube screens; those steps do not have a shell command in this chat.

### A. Open the project and authenticate

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

### B. Create and inspect the working folders

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

### C. Bootstrap IAM and build networking

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

### D. Build all three images

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

### E. Bootstrap state and update the scoped Terraform policy

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

### F. Deploy the prerequisite lab

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

### G. Test each scanner separately

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

### H. Verify CloudWatch and SNS

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

### I. Commit the work and then run the combined pipeline

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

### J. Teardown through the protected workflow

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

## Repository guide

- [Source of truth](LAB-3-SOURCE-OF-TRUTH.md) — agreed project scope and decisions.
- [Packer templates](packer/) — AMI definitions and provisioning scripts.
- [Terraform layers](terraform/) — infrastructure configurations and provider lock files.
- [GitHub workflows](.github/workflows/) — individual scans, combined pipeline, deployment and teardown.
- [Scripts](scripts/) — bootstrap and reporting automation.
- [Packer IAM bootstrap](docs/packer-builder-iam-bootstrap.md) and [Terraform GitHub Actions setup](docs/github-actions-terraform-setup.md) — operational setup details.

## Security and cost notes

Juice Shop is intentionally vulnerable. I use a restricted lab environment and do not use real customer data. My scan outputs are evidence for learning and should be reviewed before public sharing; saved Terraform plans are not suitable for blind publication.

The implementation is a portfolio lab: it uses a single self-hosted scanner, a single-AZ RDS instance, manually bootstrapped IAM and state, and a manual combined workflow. A production design would need stronger availability, runner isolation and lifecycle automation, reviewed access controls, appropriate data protection and operational processes.

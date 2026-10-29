# Lab 3 Source of Truth: Cloud-Based Secure CI/CD Pipeline

**Status:** Agreed lab scope. Treat this document as the project baseline. Do not add, remove, or change scope without the user's consent. If an agreed item appears technically incorrect or incomplete, explain the issue and propose a correction before changing this document.

## Purpose

Build a portfolio lab that deploys OWASP Juice Shop to AWS, scans it at multiple stages, records results in CloudWatch, and sends SNS notifications when scanners find vulnerabilities or exposed secrets. Findings are **report-only**: a finding must not stop deployment. Report scanner execution failures distinctly so a failed scan is never represented as clean.

Juice Shop is intentionally vulnerable. Use test data, isolate the service, restrict access to the lab, and point OWASP ZAP only at the lab target.

## Agreed tools and services

- **GitHub**: source repository for the application deployment configuration, Packer templates, Terraform, workflows, and this source-of-truth document.
- **GitHub Actions**: CI/CD orchestration.
- **Self-hosted GitHub Actions runner on its own EC2 instance**: runs jobs that need access to private SonarQube. It is separate from the application and SonarQube hosts, and from any admin host. The runner should be disposable and restricted to the intended repository/workflows.
- **GitHub OIDC and AWS IAM**: short-lived, narrowly scoped AWS access for approved workflows; no long-lived AWS keys in GitHub.
- **Gitleaks**: repository/commit secrets scanning. Never include the detected secret value in logs, artifacts, or SNS messages.
- **SonarQube and SonarScanner**: SAST and SonarQube quality-profile checks. Findings are reported; no SonarQube quality gate blocks deployment in this lab.
- **OWASP Dependency-Check**: software composition/dependency vulnerability scanning.
- **OWASP ZAP**: DAST against the deployed Juice Shop lab URL only.
- **Packer**: builds three versioned EC2 AMIs before Terraform deploys the lab.
- **Temporary Packer builder IAM role and instance profile**: bootstrapped before image builds so temporary EC2 builders can register with Systems Manager. The role receives `AmazonSSMManagedInstanceCore`; the local IAM user may pass only this role to the Packer builder. Remove the role and profile during final cleanup after image builds.
- **Terraform**: creates and destroys AWS lab infrastructure.
- **Amazon RDS for PostgreSQL**: persistent SonarQube database.
- **AWS Systems Manager (SSM)**: access/administration for EC2 hosts; no SSH or inbound SSH rules.
- **CloudWatch and CloudWatch Agent**: pipeline scan summaries and relevant EC2 logs/metrics, plus alarms.
- **Amazon SNS**: notifications when a scan reports findings; confirm the intended email subscription.

**Explicitly out of scope:** GitHub-hosted runners, Ansible and an Ansible admin node, S3, and a separately planned EBS persistence design. RDS is the agreed persistent database service. No container scanner or deployment-blocking quality gates are included. No direct SSH access, inbound SSH rules, or SSH keys are used for deployed lab hosts. Packer's temporary image builder connects through an SSM tunnel that carries its SSH communicator; this does not expose port 22.

## Packer AMIs

Packer builds the following three images. Each build uses a temporary EC2 builder that is removed after image creation; builder instances are not persistent lab servers.

1. **Juice Shop AMI**: patched/hardened base OS, minimum required packages/services, non-root application service, SSM Agent, CloudWatch Agent, and Juice Shop/runtime installed and configured to start on boot. Preserve the app's intentional vulnerabilities; isolate and restrict access to it.
2. **SonarQube AMI**: patched/hardened base OS, minimum required packages/services, non-root SonarQube service, required runtime and SonarQube version, SSM Agent, CloudWatch Agent, and startup configuration to connect to RDS. Do not bake credentials, tokens, project data, or environment-specific database endpoints into the AMI. SonarQube's local search index can be rebuilt from its database when necessary.
3. **Self-hosted runner AMI**: patched/hardened base OS, SSM Agent, CloudWatch Agent, GitHub Actions runner software, and only the tools required for the agreed scans. Do not bake runner registration tokens, AWS credentials, or SonarQube tokens into the image. Register at launch with a short-lived token supplied securely; remove/terminate the runner after its use according to the disposable-runner design.

Rebuild and version an AMI when its OS, application, scanner, runner, or baked configuration changes. Deploy the new AMI by replacing the EC2 instance; do not configure the running application host after deployment.

## NGINX decision

NGINX is **not required** to run Juice Shop. The app can listen on its application port, with Terraform security groups limiting access to approved lab sources. Packer can install and configure NGINX as a reverse proxy if the lab later needs an HTTPS/front-end proxy; that would be build-time configuration, not post-deployment configuration. NGINX does not remove Juice Shop's intentional vulnerabilities. **Do not add NGINX to the implementation scope without the user's approval.**

## Trust boundaries

For each boundary, define what crosses it, who may cross it, and which controls restrict access.

1. **Developer workstation → GitHub repository**: source, commits, pull requests, and workflow changes. Restrict repository access, review workflow changes, scan with Gitleaks, and keep credentials out of Git.
2. **GitHub repository → Actions runner**: workflow code and application code execute on the runner. Restrict who can change workflows and which events run privileged jobs; untrusted pull-request code receives no AWS deployment permissions.
3. **GitHub Actions → self-hosted runner EC2**: jobs are assigned to the runner and results are returned. Use a separate, disposable runner, restrict repository/workflow access, and do not combine it with an admin or application host.
4. **GitHub Actions → AWS account**: workflow requests AWS access. Use OIDC and a narrowly scoped role restricted to the intended repository and protected branch/environment.
5. **Runner → private SonarQube**: scanner requests and analysis results. Keep SonarQube private; allow only required runner traffic; keep a project-scoped token in protected GitHub secrets.
6. **SonarQube EC2 → RDS PostgreSQL**: database queries and stored project/analysis data. Keep RDS private, allow only SonarQube as a client, and store credentials in Secrets Manager with narrowly scoped instance access.
7. **EC2 hosts → AWS Systems Manager**: agent management traffic. Use instance roles with required SSM permissions and the required outbound path/endpoints; no SSH keys or inbound SSH.
8. **Packer → temporary EC2 builder**: base image, build scripts, packages, and application configuration. Review/version templates; bake no secrets or persistent data; remove temporary builders.
9. **Packer operator IAM user → AWS APIs and temporary builder role**: the local `mds-devsecops-lab` profile authorizes Packer to launch builders, use SSM sessions, create AMIs, and pass only the dedicated builder role. Keep the builder role limited to SSM managed-instance permissions; do not embed the user's credentials in images or user data.
10. **Terraform workflow → AWS infrastructure**: API calls to create/update/destroy resources. Review code and plans, restrict IAM/state access, and handle RDS snapshot creation/deletion as explicit steps separate from Terraform destroy.
11. **Lab users → Juice Shop**: HTTP(S) requests to an intentionally vulnerable application. Isolate it, restrict inbound traffic to lab users/scanners, and use test data only.
12. **ZAP → Juice Shop**: active scan requests and responses. Authorize and limit the target to the lab URL.
13. **Hosts and scan jobs → CloudWatch**: host logs and scan summaries. Send only necessary data, redact secrets/sensitive content, and restrict log access.
14. **CloudWatch/workflow → SNS → lab operator**: scan notifications. Keep messages concise, never include secret values, restrict publishers/subscribers, and confirm the email subscription.

## Implementation sequence

1. **Prepare the repository.** Store the Packer templates, Terraform, workflow definitions, application deployment configuration, and supporting docs. Keep credentials out of source and AMIs.
2. **Bootstrap the Packer builder role and instance profile.** Before building AMIs, create a dedicated EC2 role trusted by `ec2.amazonaws.com`, attach only `AmazonSSMManagedInstanceCore`, and add it to an instance profile. Use the `mds-devsecops-lab` AWS CLI profile; it needs narrowly scoped EC2/Packer and SSM-session permissions plus `iam:PassRole` limited to this role. Do not use root credentials. This role is a build prerequisite because Terraform has not yet created the lab IAM resources.
3. **Build the three AMIs with Packer.** Bake the patched OS, required hardening, SSM/CloudWatch agents, and each role's software. Verify versions and startup behavior. Use Packer's SSM tunnel for the temporary builder (no inbound SSH rule or key); Packer removes temporary builders.
4. **Configure GitHub OIDC and AWS IAM.** Restrict the trust relationship to the repository and approved deployment branch/environment; grant only required permissions.
5. **Provision the lab with Terraform.** Create VPC/subnets, security groups, IAM roles, RDS PostgreSQL, CloudWatch log groups/alarms, SNS topic/subscription, and three EC2 roles from the AMIs: Juice Shop, SonarQube, and runner. Keep private services private and allow only required traffic.
6. **Configure SonarQube.** Connect the SonarQube host to RDS using credentials fetched securely at runtime. Set up the project, quality profile, and project-scoped analysis token.
7. **Register the disposable runner.** Launch from its AMI, register using a short-lived token supplied securely, allow only intended workflows, and verify private access to SonarQube. Do not use it as an admin node.
8. **Use SSM for administration.** Confirm SSM Agent registration and access on EC2 hosts. Do not enable inbound SSH or use SSH keys.
9. **Set up CloudWatch and SNS.** Configure CloudWatch Agent host logs/metrics where needed, create log groups, alarms, SNS topic and confirmed email subscription. Ensure messages never contain Gitleaks secret values.
10. **Implement GitHub Actions scan jobs.** Run Gitleaks, SonarScanner, and Dependency-Check. Preserve reports and publish structured summaries (tool, commit, target, severity counts, timestamp, report reference) to CloudWatch; notify via SNS for findings.
11. **Deploy the application.** Use the approved workflow and OIDC role to deploy/replace the Juice Shop EC2 from its Packer AMI via Terraform. No post-deployment configuration of the application host.
12. **Run ZAP DAST.** Scan only the deployed lab URL. Upload/report results and publish CloudWatch/SNS summaries.
13. **Keep findings report-only.** Vulnerabilities or secret findings do not fail the workflow or stop deployment. Report tool/infrastructure execution failures separately so they are not mistaken for clean scan results.
14. **Review and document.** Review GitHub Actions summaries/artifacts, SonarQube profile results, Dependency-Check, ZAP, CloudWatch logs/alarms, SNS messages, Terraform output, and Packer AMI versions.
15. **Snapshot, destroy, and clean up.** If demonstrating backup, manually create and verify an RDS snapshot before teardown. Run `terraform destroy` for Terraform-managed lab resources. Then separately delete the manual snapshot, Packer AMIs and backing snapshots, runner registration if still present, the temporary Packer builder role and instance profile, and other retained lab resources. Verify no billable lab resources remain. Packer and Terraform do not automatically perform this complete cleanup of each other's artifacts.

## Expected AWS footprint

When all services are running: **three EC2 instances** (Juice Shop, SonarQube, and the separate self-hosted runner) plus **one RDS PostgreSQL DB instance**. SonarQube and the runner may be stopped/removed between lab sessions as planned. Packer builders are temporary and removed after image creation. The Packer builder role/profile is a temporary IAM prerequisite, not an instance. No Ansible admin node is part of the scope.

## Change control

This file is the agreed source of truth. Do not silently add or remove tools, AWS resources, scan behavior, or architecture. If implementation exposes a technical error or a necessary omission, explain the impact and proposed adjustment and get the user's consent before changing this document.


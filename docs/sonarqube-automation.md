# Automated SonarQube project configuration

The manually dispatched SonarQube project setup workflow runs on the AWS scanner runner, on master only. It reconciles a private project named project-3-juice-shop and assigns the installed Sonar way quality profiles for JavaScript, TypeScript, HTML and CSS. Reruns reuse the project. Missing profiles, authentication failures and API failures stop setup; vulnerability findings remain report-only in the later analysis workflow.

## One-time credential bootstrap

Create the GitHub environment sonarqube-admin with master as the allowed deployment branch, a required reviewer, self-review allowed for this solo lab and administrator bypass disabled. Add:
- Environment variable SONAR_HOST_URL: the current private SonarQube URL, currently http://10.20.11.99:9000.
- Environment secret SONAR_ADMIN_TOKEN: a SonarQube user token belonging to an account permitted to create projects and administer quality profiles. Set an expiration. Change the initial SonarQube administrator password before issuing this token. Do not put a password or token in Git, workflow inputs, logs or AMIs.

This initial token cannot be created by an unauthenticated API caller. It is a bootstrap prerequisite. Future analysis jobs must use a separate project analysis token; never give this administration token to scanner jobs. Project analysis token generation/rotation and the analysis workflow are subsequent implementation steps, not provided by this setup workflow.

The URL currently uses HTTP inside the existing restricted VPC boundary. The token travels over that private connection without TLS; HTTPS requires a separately reviewed transport configuration. Update SONAR_HOST_URL after replacement if the private IP changes.

## Run

After merging, use Actions > SonarQube project setup > Run workflow > master, then approve the protected environment deployment. Or:
```bash
gh workflow run sonarqube-setup.yml --ref master
gh run list --workflow sonarqube-setup.yml --limit 3
```

The workflow uploads a non-secret configuration receipt. It calls SonarQube application APIs; it installs no packages and modifies no EC2 host files. Configuration persists in RDS.

Validation still required: first authenticated execution against this installed SonarQube version, followed by a second execution to confirm reconciliation. API endpoints can change by version; use the running server's /web_api documentation if a call fails. No AWS deployment is triggered by this workflow.

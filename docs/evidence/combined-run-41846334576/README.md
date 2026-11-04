# Combined pipeline scan evidence

These reports are from [combined pipeline run 41846334576](https://github.com/DelaneKay/project-3-secure-cicd-pipeline/actions/runs/41846334576), completed on 4 November 2026. They are a point-in-time lab record; findings do not block deployment.

| Scanner | Download report | Recorded result |
| --- | --- | --- |
| Gitleaks | [gitleaks.zip](gitleaks.zip) | 0 suspected secrets |
| SonarQube | [sonarqube.zip](sonarqube.zip) | 272 issues; quality status OK |
| OWASP Dependency-Check | [dependency-check.zip](dependency-check.zip) | 20 vulnerable dependencies, 66 vulnerability occurrences; limited coverage |
| OWASP ZAP | [zap.zip](zap.zip) | 5 alert types: 2 medium and 3 informational; limited coverage |

Download each ZIP, extract it locally, then open the included HTML or JSON files. SonarQube also includes a CSV issue export. GitHub may show a binary preview for ZIP files.

Private IPv4 addresses in the archived copies have been replaced with `[redacted-private-ip]`. The original Actions artifacts were not changed. These archived copies were checked for common token patterns, but automated checks cannot prove absence of sensitive data.

Dependency-Check's packaged Node.js scan had no top-level lockfile and npm audit was unavailable; false negatives are possible. The ZAP scan used an unauthenticated traditional spider and a bounded active scan; its coverage of the JavaScript application is limited. Finding counts do not necessarily represent unique vulnerabilities.

The Terraform plan artifacts from this run are not included here. Saved plans may contain sensitive values and require a separate review before public distribution.

## CloudWatch delivery evidence

[View the saved CloudWatch summary results](../cloudwatch-scan-summaries.md). The record includes all four summaries for this combined run and also identifies earlier execution failures and later Gitleaks findings from separate runs.

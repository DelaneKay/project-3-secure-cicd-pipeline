# SonarQube scan reporting

Configure SONAR_REPORT_TOKEN in the sonarqube-scan GitHub environment. Use a User Token from a dedicated non-administrator SonarQube account with Browse permission only for project-3-juice-shop. Check inherited group permissions; do not reuse the administrative setup token. The existing SONAR_TOKEN remains the separate project analysis token.

Apply the reviewed Terraform compute IAM update before running the workflow. It grants the runner KMS data-key/decrypt access only through SNS and the aws/sns key alias for the existing encrypted topic. Existing CloudWatch and SNS destination permissions are reused. Confirm the Terraform notification_email is configured and the SNS email subscription is confirmed.

The workflow polls the submitted computation task for up to ten minutes. On success it exports all unresolved issues, with pagination, as JSON and spreadsheet-safe CSV; source excerpts and messages are omitted. Quality status is saved separately. This is not an export of resolved issues or security hotspots. A 10,000-issue API limit causes a reporting failure rather than claiming a complete export.

One aggregate summary is sent to /project-3/pipeline/scans per workflow attempt. One SNS publish is attempted if there are issues, a non-OK quality status, or an execution/report-collection failure. Clean scans produce no SNS notification. Notifications contain no individual issues or detected secret values. AWS delivery failures fail the reporting step and are visible in Actions; reports still upload. SNS delivery can duplicate messages; this is one publish attempt, not an exactly-once delivery guarantee.

A failed scanner or failed API export is never classified as clean. Findings and failed quality gates do not fail the reporting script; execution and delivery errors do. The workflow is separate from Terraform deployment and does not block it.

Reports use the task's analysis ID for quality status. Issue search returns the project's current unresolved issues; avoid simultaneous scans outside this workflow so issue snapshots correspond to the submitted analysis. Source commit and workflow URL identify the run. Reports stay in GitHub artifacts for seven days.

Validation pending: authenticated reporting API access on the lab version, completed export pagination, CloudWatch delivery, confirmed SNS email delivery, and execution-failure path. Private HTTP transport to SonarQube remains as previously documented.

# CloudWatch scan-summary verification results

I queried `/project-3/pipeline/scans` in `us-east-1` and saved this output from my WSL verification. This is a point-in-time record supplied on 4 November 2026, not a live view. The timestamps below are the summary payload timestamps in UTC. The private SonarQube dashboard address has been redacted.

## What I verified

The supplied output contains 19 summary events, covering Gitleaks, SonarQube, OWASP Dependency-Check and OWASP ZAP. All four scanners have an event for [combined pipeline run 41846334576](https://github.com/DelaneKay/project-3-secure-cicd-pipeline/actions/runs/41846334576). This demonstrates that these summary records were queryable in CloudWatch; it does not by itself prove SNS email delivery.

| Scanner in combined run | Recorded status | Result |
| --- | --- | --- |
| Gitleaks | `completed` | 0 findings |
| SonarQube | `completed` | 272 issues: 104 blocker, 10 critical, 96 major and 62 minor; quality status `OK` |
| Dependency-Check | `completed_limited_coverage` | 16,284 dependencies; 20 vulnerable dependencies; 66 occurrences: 23 critical, 13 high, 24 medium and 6 low |
| ZAP | `completed` | 5 alert types: 2 medium and 3 informational; limited unauthenticated coverage |

The output also preserves three earlier Dependency-Check `execution_failed` events. These are failed executions, not clean scans. Later Gitleaks runs `41899312704`, `41903407041` and `41910739357` each reported **5 findings**. This summary does not establish what those matches were or whether they were false positives; I need the corresponding redacted Gitleaks reports to assess them. The archived Gitleaks ZIP below belongs to the earlier combined run and cannot explain those later findings.

## All returned events

| Stream | Payload timestamp (UTC) | Status | Recorded result | Workflow |
| --- | --- | --- | --- | --- |
| `dependency-check-41719010612-1` | 2026-11-03T21:32:05.634403+00:00 | `execution_failed` | Execution failed (RuntimeError) | [Run 41719010612](https://github.com/DelaneKay/project-3-secure-cicd-pipeline/actions/runs/41719010612) |
| `dependency-check-41805796407-1` | 2026-11-04T09:17:38.122549+00:00 | `execution_failed` | Execution failed (RuntimeError) | [Run 41805796407](https://github.com/DelaneKay/project-3-secure-cicd-pipeline/actions/runs/41805796407) |
| `dependency-check-41810041572-1` | 2026-11-04T09:52:01.728839+00:00 | `execution_failed` | Execution failed (RuntimeError) | [Run 41810041572](https://github.com/DelaneKay/project-3-secure-cicd-pipeline/actions/runs/41810041572) |
| `dependency-check-41812226381-1` | 2026-11-04T10:11:54.775402+00:00 | `completed_limited_coverage` | 20 vulnerable dependencies; 66 occurrences | [Run 41812226381](https://github.com/DelaneKay/project-3-secure-cicd-pipeline/actions/runs/41812226381) |
| `zap-41832567685-1` | 2026-11-04T12:52:01.108934+00:00 | `completed` | 5 alert types | [Run 41832567685](https://github.com/DelaneKay/project-3-secure-cicd-pipeline/actions/runs/41832567685) |
| `gitleaks-41840776483-1` | 2026-11-04T13:44:02.145353+00:00 | `completed` | 0 potential secret findings | [Run 41840776483](https://github.com/DelaneKay/project-3-secure-cicd-pipeline/actions/runs/41840776483) |
| `sonarqube-41840776414-1` | 2026-11-04T13:45:18.548543+00:00 | `completed` | 272 issues; quality status OK | [Run 41840776414](https://github.com/DelaneKay/project-3-secure-cicd-pipeline/actions/runs/41840776414) |
| `dependency-check-41840776461-1` | 2026-11-04T13:48:45.607555+00:00 | `completed_limited_coverage` | 20 vulnerable dependencies; 66 occurrences | [Run 41840776461](https://github.com/DelaneKay/project-3-secure-cicd-pipeline/actions/runs/41840776461) |
| `gitleaks-41846334576-1` | 2026-11-04T14:19:09.452507+00:00 | `completed` | 0 potential secret findings | [Run 41846334576](https://github.com/DelaneKay/project-3-secure-cicd-pipeline/actions/runs/41846334576) |
| `dependency-check-41846334576-1` | 2026-11-04T14:22:06.756053+00:00 | `completed_limited_coverage` | 20 vulnerable dependencies; 66 occurrences | [Run 41846334576](https://github.com/DelaneKay/project-3-secure-cicd-pipeline/actions/runs/41846334576) |
| `sonarqube-41846334576-1` | 2026-11-04T14:23:23.441209+00:00 | `completed` | 272 issues; quality status OK | [Run 41846334576](https://github.com/DelaneKay/project-3-secure-cicd-pipeline/actions/runs/41846334576) |
| `zap-41846334576-1` | 2026-11-04T14:52:44.662661+00:00 | `completed` | 5 alert types | [Run 41846334576](https://github.com/DelaneKay/project-3-secure-cicd-pipeline/actions/runs/41846334576) |
| `gitleaks-41851649458-1` | 2026-11-04T14:52:54.335392+00:00 | `completed` | 0 potential secret findings | [Run 41851649458](https://github.com/DelaneKay/project-3-secure-cicd-pipeline/actions/runs/41851649458) |
| `gitleaks-41868766765-1` | 2026-11-04T16:35:18.046792+00:00 | `completed` | 0 potential secret findings | [Run 41868766765](https://github.com/DelaneKay/project-3-secure-cicd-pipeline/actions/runs/41868766765) |
| `gitleaks-41869320359-1` | 2026-11-04T16:38:18.808477+00:00 | `completed` | 0 potential secret findings | [Run 41869320359](https://github.com/DelaneKay/project-3-secure-cicd-pipeline/actions/runs/41869320359) |
| `gitleaks-41883558087-1` | 2026-11-04T18:05:27.344207+00:00 | `completed` | 0 potential secret findings | [Run 41883558087](https://github.com/DelaneKay/project-3-secure-cicd-pipeline/actions/runs/41883558087) |
| `gitleaks-41899312704-1` | 2026-11-04T19:41:14.168633+00:00 | `completed` | 5 potential secret findings | [Run 41899312704](https://github.com/DelaneKay/project-3-secure-cicd-pipeline/actions/runs/41899312704) |
| `gitleaks-41903407041-1` | 2026-11-04T20:06:38.265151+00:00 | `completed` | 5 potential secret findings | [Run 41903407041](https://github.com/DelaneKay/project-3-secure-cicd-pipeline/actions/runs/41903407041) |
| `gitleaks-41910739357-1` | 2026-11-04T20:52:43.016996+00:00 | `completed` | 5 potential secret findings | [Run 41910739357](https://github.com/DelaneKay/project-3-secure-cicd-pipeline/actions/runs/41910739357) |

## Saved query output

I preserved the returned `Stream` and `Summary` fields. `Summary` remains a JSON-encoded string, as returned by the CLI query. The dashboard host is the only redacted field.

```json
[
  {
    "Stream": "dependency-check-41719010612-1",
    "Summary": "{\"tool\":\"OWASP Dependency-Check\",\"project\":\"juice-shop\",\"version\":\"20.3.0\",\"status\":\"execution_failed\",\"run\":\"https://github.com/DelaneKay/project-3-secure-cicd-pipeline/actions/runs/41719010612\",\"timestamp\":\"2026-11-03T21:32:05.634403+00:00\",\"source_commit\":\"f189f521266f42c6bd05884468292000cee852ed\",\"error_category\":\"RuntimeError\"}"
  },
  {
    "Stream": "dependency-check-41805796407-1",
    "Summary": "{\"tool\":\"OWASP Dependency-Check\",\"project\":\"juice-shop\",\"version\":\"20.3.0\",\"status\":\"execution_failed\",\"run\":\"https://github.com/DelaneKay/project-3-secure-cicd-pipeline/actions/runs/41805796407\",\"timestamp\":\"2026-11-04T09:17:38.122549+00:00\",\"source_commit\":\"f189f521266f42c6bd05884468292000cee852ed\",\"error_category\":\"RuntimeError\"}"
  },
  {
    "Stream": "dependency-check-41810041572-1",
    "Summary": "{\"tool\":\"OWASP Dependency-Check\",\"project\":\"juice-shop\",\"version\":\"20.3.0\",\"status\":\"execution_failed\",\"run\":\"https://github.com/DelaneKay/project-3-secure-cicd-pipeline/actions/runs/41810041572\",\"timestamp\":\"2026-11-04T09:52:01.728839+00:00\",\"source_commit\":\"f189f521266f42c6bd05884468292000cee852ed\",\"error_category\":\"RuntimeError\"}"
  },
  {
    "Stream": "dependency-check-41812226381-1",
    "Summary": "{\"tool\":\"OWASP Dependency-Check\",\"project\":\"juice-shop\",\"version\":\"20.3.0\",\"status\":\"completed_limited_coverage\",\"run\":\"https://github.com/DelaneKay/project-3-secure-cicd-pipeline/actions/runs/41812226381\",\"timestamp\":\"2026-11-04T10:11:54.775402+00:00\",\"source_commit\":\"f189f521266f42c6bd05884468292000cee852ed\",\"coverage\":\"packaged Node.js dependencies; no top-level lockfile; npm audit unavailable; false negatives possible\",\"dependencies\":16284,\"vulnerable_dependencies\":20,\"vulnerability_occurrences\":66,\"severities\":{\"HIGH\":13,\"CRITICAL\":23,\"MEDIUM\":24,\"LOW\":6}}"
  },
  {
    "Stream": "zap-41832567685-1",
    "Summary": "{\"tool\":\"OWASP ZAP\",\"project\":\"juice-shop\",\"status\":\"completed\",\"coverage\":\"unauthenticated traditional spider and bounded active scan; coverage is limited\",\"run\":\"https://github.com/DelaneKay/project-3-secure-cicd-pipeline/actions/runs/41832567685\",\"timestamp\":\"2026-11-04T12:52:01.108934+00:00\",\"alert_types\":5,\"severities\":{\"MEDIUM\":2,\"INFORMATIONAL\":3}}"
  },
  {
    "Stream": "gitleaks-41840776483-1",
    "Summary": "{\"tool\":\"Gitleaks\",\"status\":\"completed\",\"run\":\"https://github.com/DelaneKay/project-3-secure-cicd-pipeline/actions/runs/41840776483\",\"timestamp\":\"2026-11-04T13:44:02.145353+00:00\",\"findings\":0}"
  },
  {
    "Stream": "sonarqube-41840776414-1",
    "Summary": "{\"tool\":\"SonarQube\",\"project\":\"project-3-juice-shop\",\"status\":\"completed\",\"run\":\"https://github.com/DelaneKay/project-3-secure-cicd-pipeline/actions/runs/41840776414\",\"timestamp\":\"2026-11-04T13:45:18.548543+00:00\",\"dashboard\":\"http://[redacted-private-ip]:9000/dashboard?id=project-3-juice-shop\",\"source_commit\":\"f189f521266f42c6bd05884468292000cee852ed\",\"analysis_id\":\"52cd7d90-3694-4b69-8542-a7794d5ac89e\",\"issue_count\":272,\"severities\":{\"MINOR\":62,\"MAJOR\":96,\"BLOCKER\":104,\"CRITICAL\":10},\"quality_status\":\"OK\"}"
  },
  {
    "Stream": "dependency-check-41840776461-1",
    "Summary": "{\"tool\":\"OWASP Dependency-Check\",\"project\":\"juice-shop\",\"version\":\"20.3.0\",\"status\":\"completed_limited_coverage\",\"run\":\"https://github.com/DelaneKay/project-3-secure-cicd-pipeline/actions/runs/41840776461\",\"timestamp\":\"2026-11-04T13:48:45.607555+00:00\",\"source_commit\":\"f189f521266f42c6bd05884468292000cee852ed\",\"coverage\":\"packaged Node.js dependencies; no top-level lockfile; npm audit unavailable; false negatives possible\",\"dependencies\":16284,\"vulnerable_dependencies\":20,\"vulnerability_occurrences\":66,\"severities\":{\"HIGH\":13,\"CRITICAL\":23,\"MEDIUM\":24,\"LOW\":6}}"
  },
  {
    "Stream": "gitleaks-41846334576-1",
    "Summary": "{\"tool\":\"Gitleaks\",\"status\":\"completed\",\"run\":\"https://github.com/DelaneKay/project-3-secure-cicd-pipeline/actions/runs/41846334576\",\"timestamp\":\"2026-11-04T14:19:09.452507+00:00\",\"findings\":0}"
  },
  {
    "Stream": "dependency-check-41846334576-1",
    "Summary": "{\"tool\":\"OWASP Dependency-Check\",\"project\":\"juice-shop\",\"version\":\"20.3.0\",\"status\":\"completed_limited_coverage\",\"run\":\"https://github.com/DelaneKay/project-3-secure-cicd-pipeline/actions/runs/41846334576\",\"timestamp\":\"2026-11-04T14:22:06.756053+00:00\",\"source_commit\":\"f189f521266f42c6bd05884468292000cee852ed\",\"coverage\":\"packaged Node.js dependencies; no top-level lockfile; npm audit unavailable; false negatives possible\",\"dependencies\":16284,\"vulnerable_dependencies\":20,\"vulnerability_occurrences\":66,\"severities\":{\"HIGH\":13,\"CRITICAL\":23,\"MEDIUM\":24,\"LOW\":6}}"
  },
  {
    "Stream": "sonarqube-41846334576-1",
    "Summary": "{\"tool\":\"SonarQube\",\"project\":\"project-3-juice-shop\",\"status\":\"completed\",\"run\":\"https://github.com/DelaneKay/project-3-secure-cicd-pipeline/actions/runs/41846334576\",\"timestamp\":\"2026-11-04T14:23:23.441209+00:00\",\"dashboard\":\"http://[redacted-private-ip]:9000/dashboard?id=project-3-juice-shop\",\"source_commit\":\"f189f521266f42c6bd05884468292000cee852ed\",\"analysis_id\":\"4ed8f944-8898-49bf-9a2d-20b89322be8f\",\"issue_count\":272,\"severities\":{\"MINOR\":62,\"MAJOR\":96,\"BLOCKER\":104,\"CRITICAL\":10},\"quality_status\":\"OK\"}"
  },
  {
    "Stream": "zap-41846334576-1",
    "Summary": "{\"tool\":\"OWASP ZAP\",\"project\":\"juice-shop\",\"status\":\"completed\",\"coverage\":\"unauthenticated traditional spider and bounded active scan; coverage is limited\",\"run\":\"https://github.com/DelaneKay/project-3-secure-cicd-pipeline/actions/runs/41846334576\",\"timestamp\":\"2026-11-04T14:52:44.662661+00:00\",\"alert_types\":5,\"severities\":{\"MEDIUM\":2,\"INFORMATIONAL\":3}}"
  },
  {
    "Stream": "gitleaks-41851649458-1",
    "Summary": "{\"tool\":\"Gitleaks\",\"status\":\"completed\",\"run\":\"https://github.com/DelaneKay/project-3-secure-cicd-pipeline/actions/runs/41851649458\",\"timestamp\":\"2026-11-04T14:52:54.335392+00:00\",\"findings\":0}"
  },
  {
    "Stream": "gitleaks-41868766765-1",
    "Summary": "{\"tool\":\"Gitleaks\",\"status\":\"completed\",\"run\":\"https://github.com/DelaneKay/project-3-secure-cicd-pipeline/actions/runs/41868766765\",\"timestamp\":\"2026-11-04T16:35:18.046792+00:00\",\"findings\":0}"
  },
  {
    "Stream": "gitleaks-41869320359-1",
    "Summary": "{\"tool\":\"Gitleaks\",\"status\":\"completed\",\"run\":\"https://github.com/DelaneKay/project-3-secure-cicd-pipeline/actions/runs/41869320359\",\"timestamp\":\"2026-11-04T16:38:18.808477+00:00\",\"findings\":0}"
  },
  {
    "Stream": "gitleaks-41883558087-1",
    "Summary": "{\"tool\":\"Gitleaks\",\"status\":\"completed\",\"run\":\"https://github.com/DelaneKay/project-3-secure-cicd-pipeline/actions/runs/41883558087\",\"timestamp\":\"2026-11-04T18:05:27.344207+00:00\",\"findings\":0}"
  },
  {
    "Stream": "gitleaks-41899312704-1",
    "Summary": "{\"tool\":\"Gitleaks\",\"status\":\"completed\",\"run\":\"https://github.com/DelaneKay/project-3-secure-cicd-pipeline/actions/runs/41899312704\",\"timestamp\":\"2026-11-04T19:41:14.168633+00:00\",\"findings\":5}"
  },
  {
    "Stream": "gitleaks-41903407041-1",
    "Summary": "{\"tool\":\"Gitleaks\",\"status\":\"completed\",\"run\":\"https://github.com/DelaneKay/project-3-secure-cicd-pipeline/actions/runs/41903407041\",\"timestamp\":\"2026-11-04T20:06:38.265151+00:00\",\"findings\":5}"
  },
  {
    "Stream": "gitleaks-41910739357-1",
    "Summary": "{\"tool\":\"Gitleaks\",\"status\":\"completed\",\"run\":\"https://github.com/DelaneKay/project-3-secure-cicd-pipeline/actions/runs/41910739357\",\"timestamp\":\"2026-11-04T20:52:43.016996+00:00\",\"findings\":5}"
  }
]
```

## Related scanner artifacts

These are the existing reviewed ZIP copies for combined run `41846334576`, not new exports of the later runs.

| Evidence | Link |
| --- | --- |
| Gitleaks JSON report and summary | [Download Gitleaks ZIP](combined-run-41846334576/gitleaks.zip) |
| SonarQube issue exports and summary | [Download SonarQube ZIP](combined-run-41846334576/sonarqube.zip) |
| Dependency-Check HTML/JSON reports | [Download Dependency-Check ZIP](combined-run-41846334576/dependency-check.zip) |
| ZAP HTML/JSON reports | [Download ZAP ZIP](combined-run-41846334576/zap.zip) |
| Artifact scope and coverage notes | [Read the evidence index](combined-run-41846334576/README.md) |

Dependency-Check scanned packaged Node.js dependencies without a top-level lockfile; npm audit was unavailable and false negatives are possible. ZAP used an unauthenticated traditional spider and bounded active scan. SonarQube issues, dependency vulnerability occurrences and ZAP alert types are different measures and should not be added together as a unique vulnerability count.

The verification commands are in the [README CloudWatch section](../../README.md#verify-the-cloudwatch-scan-summaries). They read logging data; they do not change host configuration or violate the lab's immutable deployment approach.

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
            "arn:aws:sns:us-east-1:273517699789:project-3-secure-cicd-pipeline-scan-findings",
            "--subject", "Lab 3 SonarQube scan summary", "--message", json.dumps(summary))
    except Exception:
        delivery_failed = True
        print("SNS summary delivery failed.")
raise SystemExit(1 if failed or delivery_failed else 0)

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
            "arn:aws:sns:us-east-1:273517699789:project-3-secure-cicd-pipeline-scan-findings",
            "--subject", "Lab 3 Dependency-Check scan summary", "--message", json.dumps(summary))
    except Exception:
        delivery_failed = True
        print("SNS summary delivery failed.")
raise SystemExit(1 if failed or delivery_failed else 0)

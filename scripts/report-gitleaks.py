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
            "arn:aws:sns:us-east-1:273517699789:project-3-secure-cicd-pipeline-scan-findings",
            "--subject", "Lab 3 Gitleaks scan summary", "--message", json.dumps(summary))
    except Exception:
        delivery_failed = True
        print("SNS summary delivery failed.")
raise SystemExit(1 if failed or delivery_failed else 0)

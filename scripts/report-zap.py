#!/usr/bin/env python3
"""Publish aggregate ZAP results without embedding request or response data."""
import collections
import datetime
import json
import os
from pathlib import Path
import subprocess
import time

out = Path(os.environ["REPORT_DIR"])
out.mkdir(parents=True, exist_ok=True)
summary = {
    "tool": "OWASP ZAP", "project": "juice-shop",
    "status": "execution_failed",
    "coverage": "unauthenticated traditional spider and bounded active scan; coverage is limited",
    "run": os.environ["RUN_URL"],
    "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat(),
}
failed = False
try:
    if os.environ["SCAN_OUTCOME"] != "success":
        raise RuntimeError("ZAP execution failed")
    report = json.loads((out / "zap-report.json").read_text())
    sites = report["site"]
    if not sites:
        raise RuntimeError("ZAP reported no sites")
    severities = collections.Counter()
    alerts = 0
    for site in sites:
        for alert in site.get("alerts", []):
            risk = str(alert.get("riskcode", "unknown"))
            name = {"3": "HIGH", "2": "MEDIUM", "1": "LOW", "0": "INFORMATIONAL"}.get(risk, "UNKNOWN")
            severities[name] += 1
            alerts += 1
    summary.update(status="completed", alert_types=alerts, severities=dict(severities))
except Exception as error:
    failed = True
    summary["error_category"] = type(error).__name__
    print("ZAP execution or report parsing failed.")

(out / "summary.json").write_text(json.dumps(summary, indent=2))
with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as step_summary:
    step_summary.write("### ZAP DAST summary\n\n" + json.dumps(summary) + "\n")

def aws(*args):
    result = subprocess.run(["aws", "--region", "us-east-1", *args],
                            stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
    if result.returncode:
        raise RuntimeError("AWS reporting failed")

delivery_failed = False
try:
    group = "/project-3/pipeline/scans"
    stream = "zap-" + os.environ["GITHUB_RUN_ID"] + "-" + os.environ["GITHUB_RUN_ATTEMPT"]
    aws("logs", "create-log-stream", "--log-group-name", group, "--log-stream-name", stream)
    events = [{"timestamp": int(time.time() * 1000), "message": json.dumps(summary)}]
    aws("logs", "put-log-events", "--log-group-name", group, "--log-stream-name", stream,
        "--log-events", json.dumps(events))
except Exception:
    delivery_failed = True
    print("CloudWatch summary delivery failed.")

if failed or summary.get("alert_types", 0):
    try:
        aws("sns", "publish", "--topic-arn",
            "arn:aws:sns:us-east-1:273517699789:project-3-secure-cicd-pipeline-scan-findings",
            "--subject", "Lab 3 ZAP scan summary", "--message", json.dumps(summary))
    except Exception:
        delivery_failed = True
        print("SNS summary delivery failed.")
raise SystemExit(1 if failed or delivery_failed else 0)

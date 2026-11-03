#!/usr/bin/env python3
"""Reconcile SonarQube project configuration without changing the EC2 host."""
import json
import os
import time
import urllib.error
import urllib.parse
import urllib.request

host = os.environ["SONAR_HOST_URL"].rstrip("/")
parsed = urllib.parse.urlsplit(host)
if parsed.scheme not in ("http", "https") or not parsed.hostname or parsed.username or parsed.query or parsed.fragment:
    raise SystemExit("Set SONAR_HOST_URL to the private SonarQube service URL.")
token = os.environ.get("SONAR_ADMIN_TOKEN", "")
if not token:
    raise SystemExit("SONAR_ADMIN_TOKEN must be configured in the protected environment.")
project = "project-3-juice-shop"
opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))

def api(path, data=None):
    body = urllib.parse.urlencode(data).encode() if data is not None else None
    request = urllib.request.Request(host + path, data=body,
        headers={"Authorization": "Bearer " + token})
    try:
        with opener.open(request, timeout=20) as response:
            raw = response.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as error:
        # Never print response bodies, which may contain confidential details.
        raise RuntimeError(f"SonarQube API {path.split('?')[0]} returned HTTP {error.code}") from None

for attempt in range(30):
    try:
        if api("/api/system/status").get("status") == "UP":
            break
    except (RuntimeError, urllib.error.URLError, TimeoutError):
        pass
    time.sleep(5)
else:
    raise SystemExit("SonarQube did not become healthy.")

if api("/api/authentication/validate").get("valid") is not True:
    raise SystemExit("SonarQube administrative authentication failed.")

existing = api("/api/projects/search?" + urllib.parse.urlencode({"projects": project}))
if not any(item["key"] == project for item in existing.get("components", [])):
    api("/api/projects/create", {"project": project, "name": "Project 3 OWASP Juice Shop", "visibility": "private"})

# Juice Shop uses JavaScript, TypeScript, HTML and CSS. Resolve profiles by
# language and name; stop if the installed server does not provide the profile.
assigned = []
for language in ("js", "ts", "web", "css"):
    profiles = api("/api/qualityprofiles/search?" + urllib.parse.urlencode({"language": language}))
    matches = [p for p in profiles.get("profiles", []) if p["name"] == "Sonar way" and p["language"] == language]
    if len(matches) != 1:
        raise SystemExit(f"Expected exactly one Sonar way profile for {language}.")
    api("/api/qualityprofiles/add_project",
        {"project": project, "language": language, "qualityProfile": "Sonar way"})
    assigned.append(language)

with open("sonarqube-setup.json", "w", encoding="utf-8") as report:
    json.dump({"project": project, "profiles": {lang: "Sonar way" for lang in assigned},
               "mode": "report-only", "setup": "complete"}, report, indent=2)
print("SonarQube project and quality profiles reconciled successfully.")

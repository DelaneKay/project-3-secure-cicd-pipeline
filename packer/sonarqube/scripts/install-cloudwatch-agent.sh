#!/usr/bin/env bash
set -euo pipefail

WORK_DIR="$(mktemp -d)"
GNUPGHOME="$WORK_DIR/gnupg"
AGENT_URL="https://amazoncloudwatch-agent.s3.amazonaws.com/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

mkdir -m 700 -p "$GNUPGHOME"

curl --fail --silent --show-error --location --retry 3 \
  --output "$WORK_DIR/amazon-cloudwatch-agent.gpg" \
  https://amazoncloudwatch-agent.s3.amazonaws.com/assets/amazon-cloudwatch-agent.gpg

gpg --batch --homedir "$GNUPGHOME" \
  --import "$WORK_DIR/amazon-cloudwatch-agent.gpg" >/dev/null

fingerprint="$(gpg --batch --homedir "$GNUPGHOME" --with-colons --fingerprint \
  | awk -F: '$1 == "fpr" {print $10; exit}')"

if [[ "$fingerprint" != "937616F3450B7D806CBD9725D58167303B789C72" ]]; then
  echo "CloudWatch Agent signing-key fingerprint did not match." >&2
  exit 1
fi

curl --fail --silent --show-error --location --retry 3 \
  --output "$WORK_DIR/amazon-cloudwatch-agent.deb" \
  "$AGENT_URL"

curl --fail --silent --show-error --location --retry 3 \
  --output "$WORK_DIR/amazon-cloudwatch-agent.deb.sig" \
  "${AGENT_URL}.sig"

gpg --batch --homedir "$GNUPGHOME" \
  --verify "$WORK_DIR/amazon-cloudwatch-agent.deb.sig" \
  "$WORK_DIR/amazon-cloudwatch-agent.deb"

dpkg -i "$WORK_DIR/amazon-cloudwatch-agent.deb"

install -d -m 0755 /opt/aws/amazon-cloudwatch-agent/etc

cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<'JSON'
{
  "agent": {
    "metrics_collection_interval": 60
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/opt/sonarqube/logs/sonar.log",
            "log_group_name": "/project-3/sonarqube",
            "log_stream_name": "{instance_id}/sonar.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/opt/sonarqube/logs/web.log",
            "log_group_name": "/project-3/sonarqube",
            "log_stream_name": "{instance_id}/web.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/opt/sonarqube/logs/ce.log",
            "log_group_name": "/project-3/sonarqube",
            "log_stream_name": "{instance_id}/ce.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/opt/sonarqube/logs/es.log",
            "log_group_name": "/project-3/sonarqube",
            "log_stream_name": "{instance_id}/es.log",
            "timezone": "UTC"
          }
        ]
      }
    }
  },
  "metrics": {
    "namespace": "Project3/SonarQube",
    "metrics_collected": {
      "mem": {
        "measurement": ["mem_used_percent"]
      },
      "disk": {
        "measurement": ["used_percent"],
        "resources": ["/"]
      }
    }
  }
}
JSON

chmod 0644 /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json

#!/usr/bin/env bash
set -Eeuo pipefail
umask 027

: "${GITHUB_RUNNER_VERSION:?GITHUB_RUNNER_VERSION is required}"
: "${GITLEAKS_VERSION:?GITLEAKS_VERSION is required}"
: "${SONAR_SCANNER_VERSION:?SONAR_SCANNER_VERSION is required}"
: "${DEPENDENCY_CHECK_VERSION:?DEPENDENCY_CHECK_VERSION is required}"
: "${ZAP_VERSION:?ZAP_VERSION is required}"
: "${TERRAFORM_VERSION:?TERRAFORM_VERSION is required}"
: "${AWS_CLI_VERSION:?AWS_CLI_VERSION is required}"
: "${JAVA_PACKAGE:?JAVA_PACKAGE is required}"

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get upgrade -y
apt-get install -y --no-install-recommends \
  ca-certificates curl unzip tar gzip jq git gnupg dirmngr wget \
  "${JAVA_PACKAGE}" \
  libicu74 libkrb5-3 zlib1g libssl3 libcurl4 liblttng-ust1 \
  libunwind8 libnuma1 libsecret-1-0 libgtk-3-0 libdbus-glib-1-2 \
  libx11-xcb1 libasound2t64 fonts-liberation ufw snapd

install -d -m 0755 /opt/project-3/tools /opt/actions-runner /usr/local/bin

if ! id actions-runner >/dev/null 2>&1; then
  useradd --system --create-home --home-dir /home/actions-runner \
    --shell /usr/sbin/nologin actions-runner
fi
chown -R actions-runner:actions-runner /home/actions-runner /opt/actions-runner

workdir="$(mktemp -d)"
gpg_home="$(mktemp -d)"
chmod 0700 "$gpg_home"
export GNUPGHOME="$gpg_home"

cleanup() {
  rm -rf "$workdir" "$gpg_home"
}
trap cleanup EXIT
cd "$workdir"

download() {
  printf 'Downloading %s\n' "$1"
  curl --fail --location --retry 3 --silent --show-error \
    "$1" --output "$2"
}

import_and_check_key() {
  local key_id="$1"
  local expected_fingerprint="$2"
  local actual_fingerprint

  gpg --batch --keyserver hkps://keyserver.ubuntu.com --recv-keys "$key_id"
  actual_fingerprint="$(
    gpg --batch --with-colons --fingerprint "$key_id" |
      awk -F: '$1 == "fpr" { print $10; exit }'
  )"

  if [[ "$actual_fingerprint" != "$expected_fingerprint" ]]; then
    echo "Unexpected signing-key fingerprint for $key_id" >&2
    exit 1
  fi
}

verify_sha256() {
  local expected="$1"
  local file="$2"
  printf '%s  %s\n' "$expected" "$file" | sha256sum --check --status
}

# Ensure the Ubuntu 24.04 SSM Agent is installed and running.
if ! snap list amazon-ssm-agent >/dev/null 2>&1; then
  snap install amazon-ssm-agent --classic
fi
snap start amazon-ssm-agent

# GitHub Actions runner. Verify against the digest published in GitHub's
# release API; stop if a valid SHA-256 digest is unavailable.
runner_archive="actions-runner-linux-x64-${GITHUB_RUNNER_VERSION}.tar.gz"
runner_api="https://api.github.com/repos/actions/runner/releases/tags/v${GITHUB_RUNNER_VERSION}"
runner_digest="$(
  curl --fail --location --retry 3 --silent --show-error "$runner_api" |
    jq -r --arg name "$runner_archive" \
      '.assets[] | select(.name == $name) | .digest // empty'
)"
runner_digest="${runner_digest#sha256:}"

if [[ ! "$runner_digest" =~ ^[[:xdigit:]]{64}$ ]]; then
  echo "GitHub release did not provide a valid SHA-256 digest for $runner_archive" >&2
  exit 1
fi

download \
  "https://github.com/actions/runner/releases/download/v${GITHUB_RUNNER_VERSION}/${runner_archive}" \
  "$runner_archive"
verify_sha256 "$runner_digest" "$runner_archive"
tar -xzf "$runner_archive" -C /opt/actions-runner
/opt/actions-runner/bin/installdependencies.sh
chown -R actions-runner:actions-runner /opt/actions-runner

# Gitleaks. Verify the archive against the release checksum manifest.
gitleaks_archive="gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz"
gitleaks_checksums="gitleaks_${GITLEAKS_VERSION}_checksums.txt"
gitleaks_base="https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}"

download "${gitleaks_base}/${gitleaks_archive}" "$gitleaks_archive"
download "${gitleaks_base}/${gitleaks_checksums}" "$gitleaks_checksums"

grep -E "[[:space:]]${gitleaks_archive//./\\.}$" \
  "$gitleaks_checksums" > gitleaks-check.txt
test -s gitleaks-check.txt
sha256sum --check gitleaks-check.txt

tar -xzf "$gitleaks_archive" gitleaks
install -o root -g root -m 0755 gitleaks /usr/local/bin/gitleaks

# SonarScanner CLI. Verify the pinned SHA-256 for version 8.1.0.6389.
sonar_zip="sonar-scanner-cli-${SONAR_SCANNER_VERSION}-linux-x64.zip"
sonar_url="https://binaries.sonarsource.com/Distribution/sonar-scanner-cli/${sonar_zip}"
sonar_expected="bb8f709f9cb73352f8d1260a3b3c506c0f41146754bc630762c126d795499d0b"

if [[ "$SONAR_SCANNER_VERSION" != "8.1.0.6389" ]]; then
  echo "Update and review the SonarScanner checksum before changing its pinned version." >&2
  exit 1
fi

download "$sonar_url" "$sonar_zip"
verify_sha256 "$sonar_expected" "$sonar_zip"
unzip -q "$sonar_zip" -d /opt/project-3/tools
ln -sfn \
  "/opt/project-3/tools/sonar-scanner-${SONAR_SCANNER_VERSION}-linux-x64/bin/sonar-scanner" \
  /usr/local/bin/sonar-scanner

# OWASP Dependency-Check. Verify its release signature.
dependency_check_zip="dependency-check-${DEPENDENCY_CHECK_VERSION}-release.zip"
dependency_check_url="https://github.com/dependency-check/DependencyCheck/releases/download/v${DEPENDENCY_CHECK_VERSION}"

download "${dependency_check_url}/${dependency_check_zip}" "$dependency_check_zip"
download "${dependency_check_url}/${dependency_check_zip}.asc" "${dependency_check_zip}.asc"

import_and_check_key \
  "259A55407DD6C00299E6607EFFDE55BE73A2D1ED" \
  "259A55407DD6C00299E6607EFFDE55BE73A2D1ED"
gpg --batch --verify "${dependency_check_zip}.asc" "$dependency_check_zip"

unzip -q "$dependency_check_zip" -d /opt/project-3/tools
ln -sfn /opt/project-3/tools/dependency-check/bin/dependency-check.sh \
  /usr/local/bin/dependency-check

# OWASP ZAP. Verify against the SHA-256 published for this release.
zap_archive="ZAP_${ZAP_VERSION}_Linux.tar.gz"
download \
  "https://github.com/zaproxy/zaproxy/releases/download/v${ZAP_VERSION}/${zap_archive}" \
  "$zap_archive"

if [[ "$ZAP_VERSION" == "2.17.0" ]]; then
  verify_sha256 \
    "efe799aaa3627db683b43f00c9c210aea0b75c00cc8f0a0f0434d12bb3ddde5a" \
    "$zap_archive"
else
  echo "Add and review the official SHA-256 for ZAP ${ZAP_VERSION} before building." >&2
  exit 1
fi

tar -xzf "$zap_archive" -C /opt/project-3/tools
ln -sfn "/opt/project-3/tools/ZAP_${ZAP_VERSION}/zap.sh" \
  /usr/local/bin/zap.sh

# Terraform. Verify HashiCorp's signed checksum manifest and the archive.
terraform_zip="terraform_${TERRAFORM_VERSION}_linux_amd64.zip"
terraform_base="https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}"

download "${terraform_base}/${terraform_zip}" "$terraform_zip"
download \
  "${terraform_base}/terraform_${TERRAFORM_VERSION}_SHA256SUMS" \
  terraform_SHA256SUMS
download \
  "${terraform_base}/terraform_${TERRAFORM_VERSION}_SHA256SUMS.sig" \
  terraform_SHA256SUMS.sig

import_and_check_key \
  "72D7468F" \
  "C874011F0AB405110D02105534365D9472D7468F"
gpg --batch --verify terraform_SHA256SUMS.sig terraform_SHA256SUMS

grep -E "[[:space:]]${terraform_zip//./\\.}$" terraform_SHA256SUMS |
  sha256sum --check

unzip -q "$terraform_zip" -d "$workdir"
install -o root -g root -m 0755 "$workdir/terraform" \
  /usr/local/bin/terraform

# AWS CLI v2. Verify its release signature and signing-key fingerprint.
awscli_zip="awscli-exe-linux-x86_64-${AWS_CLI_VERSION}.zip"
download "https://awscli.amazonaws.com/${awscli_zip}" "$awscli_zip"
download "https://awscli.amazonaws.com/${awscli_zip}.sig" "${awscli_zip}.sig"

import_and_check_key \
  "A6310ACC4672475C" \
  "FB5DB77FD5C118B80511ADA8A6310ACC4672475C"
gpg --batch --verify "${awscli_zip}.sig" "$awscli_zip"

unzip -q "$awscli_zip" -d "$workdir"
"$workdir/aws/install" --update

# CloudWatch Agent. Verify AWS's detached signature and key fingerprint.
cloudwatch_deb="amazon-cloudwatch-agent.deb"
download \
  https://amazoncloudwatch-agent.s3.amazonaws.com/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb \
  "$cloudwatch_deb"
download \
  https://amazoncloudwatch-agent.s3.amazonaws.com/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb.sig \
  "${cloudwatch_deb}.sig"
download \
  https://amazoncloudwatch-agent.s3.amazonaws.com/assets/amazon-cloudwatch-agent.gpg \
  amazon-cloudwatch-agent.gpg
gpg --batch --import amazon-cloudwatch-agent.gpg

cloudwatch_fingerprint="$(
  gpg --batch --with-colons --fingerprint 3B789C72 |
    awk -F: '$1 == "fpr" { print $10; exit }'
)"
if [[ "$cloudwatch_fingerprint" != "937616F3450B7D806CBD9725D58167303B789C72" ]]; then
  echo "Unexpected CloudWatch Agent signing-key fingerprint" >&2
  exit 1
fi

gpg --batch --verify "${cloudwatch_deb}.sig" "$cloudwatch_deb"
dpkg -i "$cloudwatch_deb"

# Bake CloudWatch log collection config. A systemd unit applies it after
# launch, when the deployed instance has its own IAM role and identity.
install -d -m 0755 /opt/aws/amazon-cloudwatch-agent/etc
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<'JSON'
{
  "agent": {
    "metrics_collection_interval": 60,
    "run_as_user": "root"
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/syslog",
            "log_group_name": "/project-3/github-runner",
            "log_stream_name": "{instance_id}/syslog",
            "retention_in_days": 14
          },
          {
            "file_path": "/var/log/auth.log",
            "log_group_name": "/project-3/github-runner",
            "log_stream_name": "{instance_id}/auth",
            "retention_in_days": 14
          },
          {
            "file_path": "/opt/actions-runner/_diag/Runner_*.log",
            "log_group_name": "/project-3/github-runner",
            "log_stream_name": "{instance_id}/runner",
            "retention_in_days": 14
          }
        ]
      }
    }
  }
}
JSON
chmod 0644 /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json

cat > /usr/local/sbin/project-3-start-cloudwatch-agent <<'SCRIPT'
#!/usr/bin/env bash
set -Eeuo pipefail
exec /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config -m ec2 \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json \
  -s
SCRIPT
chmod 0755 /usr/local/sbin/project-3-start-cloudwatch-agent

cat > /etc/systemd/system/project-3-cloudwatch-agent.service <<'UNIT'
[Unit]
Description=Start CloudWatch Agent with the instance runtime identity
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/project-3-start-cloudwatch-agent
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
UNIT
systemctl enable project-3-cloudwatch-agent.service

# Host firewall: no unsolicited inbound connections; outbound access remains
# available for GitHub, SSM, CloudWatch, and scanner update services.
ufw --force default deny incoming
ufw --force default allow outgoing
ufw --force enable

# Keep tool installations root-owned and remove package cache.
chown -R root:root /opt/project-3/tools
chmod -R go-w /opt/project-3/tools
chown -R actions-runner:actions-runner /home/actions-runner /opt/actions-runner
apt-get clean
rm -rf /var/lib/apt/lists/*

echo "Runner tools, SSM Agent, and CloudWatch setup completed. GitHub registration is deferred until instance launch."

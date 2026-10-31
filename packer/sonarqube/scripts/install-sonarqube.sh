#!/usr/bin/env bash
set -euo pipefail
umask 027

SONARQUBE_VERSION="${SONARQUBE_VERSION:-26.10.0.133078}"
JAVA_PACKAGE="${JAVA_PACKAGE:-openjdk-21-jdk}"
AWS_CLI_VERSION="${AWS_CLI_VERSION:-2.39.1}"
AWS_CLI_KEY_ID="A6310ACC4672475C"
AWS_CLI_KEY_FINGERPRINT="FB5DB77FD5C118B80511ADA8A6310ACC4672475C"

SONARQUBE_URL="https://binaries.sonarsource.com/Distribution/sonarqube/sonarqube-${SONARQUBE_VERSION}.zip"
AWS_CLI_ARCHIVE="awscli-exe-linux-x86_64-${AWS_CLI_VERSION}.zip"
AWS_CLI_URL="https://awscli.amazonaws.com/${AWS_CLI_ARCHIVE}"
AWS_CLI_KEY_URL="https://raw.githubusercontent.com/aws/aws-cli/v2/KEYS"

WORK_DIR="$(mktemp -d)"
SONARQUBE_JAR=""

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get full-upgrade -y
apt-get install -y \
  ca-certificates \
  curl \
  gnupg \
  jq \
  unzip \
  "$JAVA_PACKAGE"

java -version

# Install the pinned AWS CLI v2 after verifying AWS's PGP signature.
curl --fail --silent --show-error --location --retry 3 \
  --output "$WORK_DIR/awscli.zip" \
  "$AWS_CLI_URL"

curl --fail --silent --show-error --location --retry 3 \
  --output "$WORK_DIR/awscli.zip.sig" \
  "${AWS_CLI_URL}.sig"

curl --fail --silent --show-error --location --retry 3 \
  --output "$WORK_DIR/aws-cli-keys" \
  "$AWS_CLI_KEY_URL"

install -d -m 0700 "$WORK_DIR/gnupg"

gpg --homedir "$WORK_DIR/gnupg" \
  --batch \
  --import "$WORK_DIR/aws-cli-keys"

actual_fingerprint="$(
  gpg --homedir "$WORK_DIR/gnupg" \
    --batch \
    --with-colons \
    --fingerprint "$AWS_CLI_KEY_ID" \
    | awk -F: '$1 == "fpr" { print $10; exit }'
)"

if [[ "$actual_fingerprint" != "$AWS_CLI_KEY_FINGERPRINT" ]]; then
  echo "AWS CLI signing key fingerprint did not match the expected value." >&2
  exit 1
fi

gpg --homedir "$WORK_DIR/gnupg" \
  --batch \
  --verify "$WORK_DIR/awscli.zip.sig" "$WORK_DIR/awscli.zip"

unzip -q "$WORK_DIR/awscli.zip" -d "$WORK_DIR/awscli"

"$WORK_DIR/awscli/aws/install" \
  --install-dir /usr/local/aws-cli \
  --bin-dir /usr/local/bin

aws_cli_output="$(aws --version 2>&1)"
printf '%s\n' "$aws_cli_output"

if [[ "$aws_cli_output" != "aws-cli/${AWS_CLI_VERSION}"* ]]; then
  echo "Installed AWS CLI version did not match ${AWS_CLI_VERSION}." >&2
  exit 1
fi

curl --fail --silent --show-error --location \
  --retry 3 \
  --output "$WORK_DIR/sonarqube.zip" \
  "$SONARQUBE_URL"

checksum_text="$(
  curl --fail --silent --show-error --location \
    "${SONARQUBE_URL}.sha256"
)"

expected_checksum="$(
  printf '%s\n' "$checksum_text" \
    | grep -Eo '[[:xdigit:]]{64}' \
    | head -n 1
)"

if [[ ! "$expected_checksum" =~ ^[[:xdigit:]]{64}$ ]]; then
  echo "Could not read the SonarQube SHA-256 checksum." >&2
  exit 1
fi

printf '%s  %s\n' "$expected_checksum" "$WORK_DIR/sonarqube.zip" \
  | sha256sum --check

groupadd --system sonarqube 2>/dev/null || true

useradd \
  --system \
  --gid sonarqube \
  --home-dir /var/lib/sonarqube \
  --create-home \
  --shell /usr/sbin/nologin \
  sonarqube 2>/dev/null || true

unzip -q "$WORK_DIR/sonarqube.zip" -d /opt

SONARQUBE_HOME="/opt/sonarqube-${SONARQUBE_VERSION}"
ln -sfn "$SONARQUBE_HOME" /opt/sonarqube
chown -R sonarqube:sonarqube "$SONARQUBE_HOME"

SONARQUBE_JAR="$(
  find "$SONARQUBE_HOME/lib" \
    -maxdepth 1 \
    -type f \
    -name 'sonar-application-*.jar' \
    -print -quit
)"

if [[ -z "$SONARQUBE_JAR" ]]; then
  echo "SonarQube application JAR was not found." >&2
  exit 1
fi

cat > /etc/sysctl.d/99-sonarqube.conf <<'EOF'
vm.max_map_count=524288
fs.file-max=131072
EOF

sysctl --system

cat > /etc/systemd/system/sonarqube.service <<EOF
[Unit]
Description=SonarQube Community Build
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=sonarqube
Group=sonarqube
WorkingDirectory=/opt/sonarqube
ExecStart=/usr/bin/java -Xms32m -Xmx32m -Djava.net.preferIPv4Stack=true -jar ${SONARQUBE_JAR}
SuccessExitStatus=143
Restart=on-failure
RestartSec=10
TimeoutStartSec=300
LimitNOFILE=131072
LimitNPROC=8192
UMask=0027
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload

echo "SonarQube ${SONARQUBE_VERSION} and AWS CLI ${AWS_CLI_VERSION} installed."
echo "SonarQube service remains disabled until RDS configuration is supplied at launch."

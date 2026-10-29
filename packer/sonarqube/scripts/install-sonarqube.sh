#!/usr/bin/env bash
set -euo pipefail

SONARQUBE_VERSION="${SONARQUBE_VERSION:-26.10.0.133078}"
JAVA_PACKAGE="${JAVA_PACKAGE:-openjdk-21-jdk}"
SONARQUBE_URL="https://binaries.sonarsource.com/Distribution/sonarqube/sonarqube-${SONARQUBE_VERSION}.zip"
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
  unzip \
  "$JAVA_PACKAGE"

java -version

curl --fail --silent --show-error --location \
  --retry 3 \
  --output "$WORK_DIR/sonarqube.zip" \
  "$SONARQUBE_URL"

checksum_text="$(curl --fail --silent --show-error --location \
  "${SONARQUBE_URL}.sha256")"
expected_checksum="$(printf '%s\n' "$checksum_text" \
  | grep -Eo '[[:xdigit:]]{64}' \
  | head -n 1)"

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

SONARQUBE_JAR="$(find "$SONARQUBE_HOME/lib" \
  -maxdepth 1 \
  -type f \
  -name 'sonar-application-*.jar' \
  -print -quit)"

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

echo "SonarQube ${SONARQUBE_VERSION} installed. Service is not enabled until RDS configuration is supplied at launch."

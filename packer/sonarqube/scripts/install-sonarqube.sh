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

WORK_DIR="$(mktemp -d)"
SONARQUBE_JAR=""

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

download() {
  local label="$1"
  local url="$2"
  local destination="$3"
  local http_status

  printf '\nDownloading %s\nURL: %s\n' "$label" "$url"
  if http_status="$(curl \
    --fail \
    --silent \
    --show-error \
    --location \
    --retry 3 \
    --connect-timeout 20 \
    --max-time 600 \
    --output "$destination" \
    --write-out '%{http_code}' \
    "$url")"; then
    printf 'Download succeeded: %s (HTTP %s)\n' "$label" "$http_status"
  else
    printf 'Download failed: %s (HTTP %s)\nURL: %s\n' \
      "$label" "${http_status:-unknown}" "$url" >&2
    return 1
  fi
}

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

download \
  "AWS CLI v${AWS_CLI_VERSION} archive" \
  "$AWS_CLI_URL" \
  "$WORK_DIR/awscli.zip"

download \
  "AWS CLI v${AWS_CLI_VERSION} signature" \
  "${AWS_CLI_URL}.sig" \
  "$WORK_DIR/awscli.zip.sig"

cat > "$WORK_DIR/aws-cli-public-key.asc" <<'PGP'
-----BEGIN PGP PUBLIC KEY BLOCK-----

mQINBF2Cr7UBEADJZHcgusOJl7ENSyumXh85z0TRV0xJorM2B/JL0kHOyigQluUG
ZMLhENaG0bYatdrKP+3H91lvK050pXwnO/R7fB/FSTouki4ciIx5OuLlnJZIxSzx
PqGl0mkxImLNbGWoi6Lto0LYxqHN2iQtzlwTVmq9733zd3XfcXrZ3+LblHAgEt5G
TfNxEKJ8soPLyWmwDH6HWCnjZ/aIQRBTIQ05uVeEoYxSh6wOai7ss/KveoSNBbYz
gbdzoqI2Y8cgH2nbfgp3DSasaLZEdCSsIsK1u05CinE7k2qZ7KgKAUIcT/cR/grk
C6VwsnDU0OUCideXcQ8WeHutqvgZH1JgKDbznoIzeQHJD238GEu+eKhRHcz8/jeG
94zkcgJOz3KbZGYMiTh277Fvj9zzvZsbMBCedV1BTg3TqgvdX4bdkhf5cH+7NtWO
lrFj6UwAsGukBTAOxC0l/dnSmZhJ7Z1KmEWilro/gOrjtOxqRQutlIqG22TaqoPG
fYVN+en3Zwbt97kcgZDwqbuykNt64oZWc4XKCa3mprEGC3IbJTBFqglXmZ7l9ywG
EEUJYOlb2XrSuPWml39beWdKM8kzr1OjnlOm6+lpTRCBfo0wa9F8YZRhHPAkwKkX
XDeOGpWRj4ohOx0d2GWkyV5xyN14p2tQOCdOODmz80yUTgRpPVQUtOEhXQARAQAB
tCFBV1MgQ0xJIFRlYW0gPGF3cy1jbGlAYW1hem9uLmNvbT6JAlQEEwEIAD4CGwMF
CwkIBwIGFQoJCAsCBBYCAwECHgECF4AWIQT7Xbd/1cEYuAURraimMQrMRnJHXAUC
akV0ygUJDqP4lQAKCRCmMQrMRnJHXFHjD/9eyZLYcKuQOlLvtqSDtUBiEZf6ZZjM
i3ygYH8rJNtuToUH+HvSpe819urJCquXhDrlK6N+aqW0hCLtNABJG/vsafIgvIYJ
hSGgpgtNnQyMV1jViRWqPjbouw8OkYKBThUfT1i2Y+wn58ifs6ODBCmTexWtXspA
Si+Gt49xDOW0APmbOPnI+a4HJW6tVEo6MWS0WjzpiBayR3d1A4pt4YrPfSdDgpLo
h2SLQqlRqvvVZJaWBjhkErNFpfsBA06sDcPEOb0G8LBUbR4WOcdvhe5LubJbZuxC
AG9kNPCVeQP1ixwjgjXKysaxeQ6rv0VzIQgRp6tLVLWhy6AKDNvLjFSsmXZ1Wl08
Y/RlOHXlzLuQMRE6sR1wOdRxc9TsrNWTGiBK65cvSWOy03JeBkQQ8pesqltiyxI9
U21kkgiXtTSKNGfKK8pO27D81YANhRqPK7iTp6kuFiY2WtOg90KTMNlIT+Ff85Y2
b1rHj6Z0SrCkJujhWk3IBPic/wJgz01LEc/OAdUPlby90RJZcIBhSlWhT7mXnXIO
c0HWlNQrns2s3CTyYwZSiSlYe9ApeLwhjDo8NhbFuCAy61l6O5UsR4AfZxx/rGKv
2wFb1/RN/P4gNe6vmxZAPjR0AQcwD3tc2McimOLr/22kmPz8IH3I0X7WoSFr0Biz
E91G7bb0hOb/cA==
=knv7
-----END PGP PUBLIC KEY BLOCK-----
PGP

GNUPGHOME="$WORK_DIR/gnupg"
install -d -m 0700 "$GNUPGHOME"
export GNUPGHOME

gpg --batch --import "$WORK_DIR/aws-cli-public-key.asc"

actual_fingerprint="$(
  gpg --batch --with-colons --fingerprint "$AWS_CLI_KEY_ID" \
    | awk -F: '$1 == "fpr" { print $10; exit }'
)"

if [[ "$actual_fingerprint" != "$AWS_CLI_KEY_FINGERPRINT" ]]; then
  echo "AWS CLI signing key fingerprint did not match the expected value." >&2
  echo "Expected: $AWS_CLI_KEY_FINGERPRINT" >&2
  echo "Actual:   $actual_fingerprint" >&2
  exit 1
fi

if ! verify_output="$(
  gpg --batch --status-fd 1 \
    --verify "$WORK_DIR/awscli.zip.sig" "$WORK_DIR/awscli.zip" 2>&1
)"; then
  printf '%s\n' "$verify_output" >&2
  echo "AWS CLI archive signature verification failed." >&2
  exit 1
fi

printf '%s\n' "$verify_output"
if ! grep -Fq "[GNUPG:] VALIDSIG ${AWS_CLI_KEY_FINGERPRINT}" <<<"$verify_output"; then
  echo "AWS CLI archive was not signed by the expected AWS CLI key." >&2
  exit 1
fi

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

download \
  "SonarQube v${SONARQUBE_VERSION} archive" \
  "$SONARQUBE_URL" \
  "$WORK_DIR/sonarqube.zip"

download \
  "SonarQube v${SONARQUBE_VERSION} SHA-256 checksum" \
  "${SONARQUBE_URL}.sha256" \
  "$WORK_DIR/sonarqube.zip.sha256"

expected_checksum="$(
  grep -Eo '[[:xdigit:]]{64}' "$WORK_DIR/sonarqube.zip.sha256" | sed -n '1p'
)"

if [[ ! "$expected_checksum" =~ ^[[:xdigit:]]{64}$ ]]; then
  echo "Could not read the SonarQube SHA-256 checksum." >&2
  cat "$WORK_DIR/sonarqube.zip.sha256" >&2
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

if [[ ! -f /tmp/project-3-start-sonarqube ]]; then
  echo "Packer did not stage the SonarQube startup launcher." >&2
  exit 1
fi

install -o root -g root -m 0755 \
  /tmp/project-3-start-sonarqube \
  /usr/local/sbin/project-3-start-sonarqube
rm -f /tmp/project-3-start-sonarqube

cat > /etc/sysctl.d/99-sonarqube.conf <<'SYSCTL'
vm.max_map_count=524288
fs.file-max=131072
SYSCTL

sysctl --system

cat > /etc/systemd/system/sonarqube.service <<'UNIT'
[Unit]
Description=SonarQube Community Build
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=sonarqube
Group=sonarqube
WorkingDirectory=/opt/sonarqube
ExecStart=/usr/local/sbin/project-3-start-sonarqube
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
UNIT

systemctl daemon-reload
systemctl enable sonarqube.service

echo "SonarQube ${SONARQUBE_VERSION} and AWS CLI ${AWS_CLI_VERSION} installed."
echo "The baked service retrieves DB settings from instance metadata and credentials from Secrets Manager at startup."

#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get -y full-upgrade
apt-get -y install ca-certificates curl xz-utils ufw

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

# Install pinned Node.js 22 and verify it against Node.js's published checksums.
node_version="22.23.4"
node_archive="node-v${node_version}-linux-x64.tar.xz"
node_url="https://nodejs.org/dist/v${node_version}"

curl -fsSLo "$work_dir/$node_archive" "$node_url/$node_archive"
curl -fsSLo "$work_dir/SHASUMS256.txt" "$node_url/SHASUMS256.txt"
grep -F "  $node_archive" "$work_dir/SHASUMS256.txt" > "$work_dir/node.sha256"

(
  cd "$work_dir"
  sha256sum --check --strict node.sha256
)

install -d -m 0755 "/opt/node-v${node_version}"
tar -xJf "$work_dir/$node_archive" \
  --strip-components=1 \
  -C "/opt/node-v${node_version}"

# Download and verify the pinned OWASP Juice Shop release.
juice_version="20.3.0"
juice_archive="juice-shop-${juice_version}_node22_linux_x64.tgz"
juice_sha256="6148dcce8fe7d990a86bf8457a0e9a07821c127d498c76da1a3bc7dba12a77e5"
juice_url="https://github.com/juice-shop/juice-shop/releases/download/v${juice_version}/${juice_archive}"

curl -fsSLo "$work_dir/$juice_archive" "$juice_url"
printf '%s  %s\n' "$juice_sha256" "$work_dir/$juice_archive" \
  | sha256sum --check --strict

mkdir -p "$work_dir/juice-unpacked"
tar -xzf "$work_dir/$juice_archive" -C "$work_dir/juice-unpacked"

package_json="$(find "$work_dir/juice-unpacked" -maxdepth 3 \
  -type f -name package.json -print -quit)"

if [[ -z "$package_json" ]]; then
  echo "Could not find Juice Shop package.json in the release archive." >&2
  exit 1
fi

app_source="$(dirname "$package_json")"
install -d -m 0755 /opt/juice-shop
cp -a "$app_source/." /opt/juice-shop/

if ! id juiceshop >/dev/null 2>&1; then
  useradd --system \
    --home-dir /opt/juice-shop \
    --shell /usr/sbin/nologin \
    --user-group juiceshop
fi

chown -R juiceshop:juiceshop /opt/juice-shop

install -d -o juiceshop -g juiceshop -m 0750 /var/log/juice-shop
touch /var/log/juice-shop/app.log
chown juiceshop:juiceshop /var/log/juice-shop/app.log
chmod 0640 /var/log/juice-shop/app.log

# Run the intentionally vulnerable application as a dedicated non-root user.
cat > /etc/systemd/system/juice-shop.service <<'UNIT'
[Unit]
Description=OWASP Juice Shop
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=juiceshop
Group=juiceshop
WorkingDirectory=/opt/juice-shop
Environment=PATH=/opt/node-v22.23.4/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
Environment=PORT=3000
ExecStart=/opt/node-v22.23.4/bin/npm start
Restart=on-failure
RestartSec=5
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=true
StandardOutput=append:/var/log/juice-shop/app.log
StandardError=append:/var/log/juice-shop/app.log

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable juice-shop.service

# Keep SSM enabled for administration after the instance launches.
if systemctl cat amazon-ssm-agent.service >/dev/null 2>&1; then
  systemctl enable amazon-ssm-agent.service
elif command -v snap >/dev/null 2>&1 \
  && snap list amazon-ssm-agent >/dev/null 2>&1; then
  snap start amazon-ssm-agent
else
  echo "SSM Agent was not found on the Ubuntu base image." >&2
  exit 1
fi

# Install and configure CloudWatch Agent.
# Terraform will create these log groups before deploying the instance.
curl -fsSLo "$work_dir/amazon-cloudwatch-agent.deb" \
  https://amazoncloudwatch-agent.s3.amazonaws.com/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
dpkg -i "$work_dir/amazon-cloudwatch-agent.deb"

cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<'CWCONFIG'
{
  "agent": {
    "run_as_user": "root",
    "metrics_collection_interval": 60
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/syslog",
            "log_group_name": "/project-3/juice-shop/syslog",
            "log_stream_name": "{instance_id}"
          },
          {
            "file_path": "/var/log/auth.log",
            "log_group_name": "/project-3/juice-shop/auth",
            "log_stream_name": "{instance_id}"
          },
          {
            "file_path": "/var/log/juice-shop/app.log",
            "log_group_name": "/project-3/juice-shop/app",
            "log_stream_name": "{instance_id}"
          }
        ]
      }
    }
  },
  "metrics": {
    "namespace": "Project3/JuiceShop",
    "metrics_collected": {
      "mem": {
        "measurement": ["mem_used_percent"],
        "metrics_collection_interval": 60
      },
      "disk": {
        "measurement": ["used_percent"],
        "resources": ["/"],
        "metrics_collection_interval": 60
      }
    }
  }
}
CWCONFIG

chmod 0640 /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
systemctl enable amazon-cloudwatch-agent.service

# SSH is used only by Packer's SSH communicator through its SSM tunnel.
# Do not start SSH on the deployed Juice Shop host.
systemctl disable ssh.service 2>/dev/null || true
systemctl disable ssh.socket 2>/dev/null || true

# Host firewall: allow local loopback and the app port only.
# AWS security groups remain responsible for restricting port 3000 sources.
ufw default deny incoming
ufw default allow outgoing
ufw allow in on lo
ufw allow 3000/tcp comment 'Juice Shop; source access restricted by AWS security group'
ufw --force enable

apt-get clean
rm -rf /var/lib/apt/lists/*

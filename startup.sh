#!/bin/bash
set -euo pipefail

# Install dependencies
apt-get update -y
apt-get install -y curl git jq

# Install Docker
curl -fsSL https://get.docker.com | sh

# Install Buildkite agent from GitHub releases (avoids apt repo GPG issues)
VERSION=$(curl -fsSL https://api.github.com/repos/buildkite/agent/releases/latest \
  | jq -r '.tag_name' | sed 's/^v//')

curl -fsSL "https://github.com/buildkite/agent/releases/download/v$${VERSION}/buildkite-agent-linux-amd64-$${VERSION}.tar.gz" \
  | tar xz --strip-components=1 -C /usr/local/bin ./buildkite-agent

# Create system user
useradd -r -m -s /bin/bash buildkite-agent

# Add to docker group so agent can run Docker steps
usermod -aG docker buildkite-agent

# Create config and working directories
mkdir -p /etc/buildkite-agent /var/lib/buildkite-agent /var/log/buildkite-agent
chown buildkite-agent:buildkite-agent /var/lib/buildkite-agent /var/log/buildkite-agent

# Write agent config
cat > /etc/buildkite-agent/buildkite-agent.cfg <<EOF
token="${agent_token}"
tags="cloud=gcp,os=linux,arch=amd64"
build-path="/var/lib/buildkite-agent/builds"
EOF

# Write systemd unit
cat > /etc/systemd/system/buildkite-agent.service <<EOF
[Unit]
Description=Buildkite Agent
After=network.target docker.service
Requires=docker.service

[Service]
Type=simple
User=buildkite-agent
ExecStart=/usr/local/bin/buildkite-agent start --config /etc/buildkite-agent/buildkite-agent.cfg
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable buildkite-agent
systemctl start buildkite-agent

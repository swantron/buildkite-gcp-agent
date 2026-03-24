#!/bin/bash
set -euo pipefail

# Install dependencies
apt-get update -y
apt-get install -y ca-certificates curl git jq

# Install Docker via official apt repository
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$${VERSION_CODENAME}") stable" \
  > /etc/apt/sources.list.d/docker.list
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Install Node.js 20
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y nodejs

# Install Yarn
npm install -g yarn

# Install Go
GO_VERSION=$(curl -fsSL https://go.dev/VERSION?m=text | head -1)
curl -fsSL "https://dl.google.com/go/$${GO_VERSION}.linux-amd64.tar.gz" | tar xz -C /usr/local
ln -sf /usr/local/go/bin/go /usr/local/bin/go
ln -sf /usr/local/go/bin/gofmt /usr/local/bin/gofmt

# Install common Go tools used by pipelines
GOPATH=/root/go /usr/local/bin/go install gotest.tools/gotestsum@latest
ln -sf /root/go/bin/gotestsum /usr/local/bin/gotestsum

# Install Buildkite agent from GitHub releases (avoids apt repo GPG issues)
VERSION=$(curl -fsSL https://api.github.com/repos/buildkite/agent/releases/latest \
  | jq -r '.tag_name' | sed 's/^v//')

curl -fsSL "https://github.com/buildkite/agent/releases/download/v$${VERSION}/buildkite-agent-linux-amd64-$${VERSION}.tar.gz" \
  | tar xz --strip-components=1 -C /usr/local/bin ./buildkite-agent

# Create system user
useradd -r -m -s /bin/bash buildkite-agent

# Add to docker group so agent can run Docker steps
usermod -aG docker buildkite-agent

# Install SSH key so the agent can clone from GitHub without manual setup.
# The key is injected from a GitHub secret via Terraform templatefile,
# so reprovisioning the instance never requires manual key management.
mkdir -p /home/buildkite-agent/.ssh
chmod 700 /home/buildkite-agent/.ssh

cat > /home/buildkite-agent/.ssh/id_ed25519 <<'SSHKEY'
${ssh_private_key}
SSHKEY

chmod 600 /home/buildkite-agent/.ssh/id_ed25519
chown -R buildkite-agent:buildkite-agent /home/buildkite-agent/.ssh

# Pre-trust GitHub to prevent host key prompts blocking the first clone
ssh-keyscan github.com >> /home/buildkite-agent/.ssh/known_hosts
chown buildkite-agent:buildkite-agent /home/buildkite-agent/.ssh/known_hosts

# Create config, working, and plugin cache directories
mkdir -p /etc/buildkite-agent /var/lib/buildkite-agent /var/log/buildkite-agent /var/cache/buildkite-agent
chown buildkite-agent:buildkite-agent /var/lib/buildkite-agent /var/log/buildkite-agent /var/cache/buildkite-agent

# Write agent config
cat > /etc/buildkite-agent/buildkite-agent.cfg <<EOF
token="${agent_token}"
tags="queue=gcp,cloud=gcp,os=linux,arch=amd64"
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

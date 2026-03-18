#!/bin/bash
set -euo pipefail

# Install dependencies
apt-get update -y
apt-get install -y curl git jq

# Install Docker (needed for most CI workloads)
curl -fsSL https://get.docker.com | sh

# Install Buildkite agent
curl -fsSL https://packages.buildkite.com/buildkite/agent/gpgkey \
  | gpg --dearmor -o /usr/share/keyrings/buildkite-agent-archive-keyring.gpg

echo "deb [signed-by=/usr/share/keyrings/buildkite-agent-archive-keyring.gpg] https://apt.buildkite.com/buildkite-agent stable main" \
  | tee /etc/apt/sources.list.d/buildkite-agent.list

apt-get update -y
apt-get install -y buildkite-agent

# Add buildkite-agent user to docker group (user created by package install above)
usermod -aG docker buildkite-agent

# Configure agent token
sed -i "s/xxx/${agent_token}/g" /etc/buildkite-agent/buildkite-agent.cfg

# Set agent tags for pipeline targeting
cat >> /etc/buildkite-agent/buildkite-agent.cfg <<EOF
tags="cloud=gcp,os=linux,arch=amd64"
EOF

# Enable and start
systemctl enable buildkite-agent
systemctl start buildkite-agent

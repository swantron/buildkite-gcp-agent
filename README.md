# buildkite-gcp-agent

Terraform config to provision a self-hosted [Buildkite](https://buildkite.com) agent on GCP. Runs on a free-tier `e2-micro` instance in `us-central1`.

## What it provisions

- `e2-micro` Compute Engine instance (Debian 12, 30GB standard disk)
- Buildkite agent installed and registered via startup script
- Docker installed for containerized build steps
- Optional SSH firewall rule (restrict via `ssh_source_ranges`)

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.5
- [gcloud CLI](https://cloud.google.com/sdk/docs/install) authenticated (`gcloud auth application-default login`)
- A [Buildkite account](https://buildkite.com) — free for open source
- A GCP project with Compute Engine API enabled

## Setup

1. **Get your Buildkite agent token**
   - Buildkite UI → Agents → New Agent → copy the token

2. **Configure variables**
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   # edit terraform.tfvars with your project_id and agent token
   ```

3. **Apply**
   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

4. **Verify the agent connected**
   - Buildkite UI → Agents — your agent should appear within ~2 minutes
   - Or check logs directly:
   ```bash
   # shown in terraform output after apply
   gcloud compute ssh buildkite-agent --zone us-central1-a --project YOUR_PROJECT \
     --command 'journalctl -u buildkite-agent -f'
   ```

## Teardown

```bash
terraform destroy
```

The instance is the only billable resource. Destroying it stops all costs immediately.

## Agent tags

The agent registers with `cloud=gcp,os=linux,arch=amd64`. Use these in your pipeline to target this agent:

```yaml
# .buildkite/pipeline.yml
steps:
  - label: "build"
    command: "make build"
    agents:
      cloud: gcp
```

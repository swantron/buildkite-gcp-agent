# buildkite-gcp-agent

Terraform config to provision a self-hosted [Buildkite](https://buildkite.com) agent on GCP, applied automatically via GitHub Actions.

## Architecture

```
GitHub (this repo)
  └── GitHub Actions (terraform plan / apply)
        └── GCP Compute Engine e2-micro (us-west1)
              └── Buildkite Agent (polls Buildkite for jobs)
                    └── Buildkite (orchestrates pipelines)
                          └── Application repos (.buildkite/pipeline.yml)
```

### Why this split?

**GHA manages infrastructure, Buildkite runs builds.** This is an intentional division of responsibility:

- **Infrastructure lifecycle** (provision/update/destroy an agent) is infrequent, requires cloud credentials, and benefits from a PR review + plan-before-apply workflow. GitHub Actions is the right tool — it has native access to repo secrets and a straightforward event model for merge-gated changes.

- **Build workloads** (test, compile, release) are frequent, benefit from agent flexibility (custom hardware, Docker, specific toolchains), and need Buildkite-specific features like dynamic pipelines, parallel step matrices, and annotations. Buildkite runs these on the agent GHA provisioned.

This also avoids a circularity problem: Buildkite can't provision itself. GHA bootstraps the agent, then steps out of the way.

### Why GCS for Terraform state?

Terraform state must live somewhere persistent and shared — not a developer's laptop. A GCS bucket gives us:
- Consistent state across GHA runs
- State locking (prevents concurrent applies)
- Free within GCP free tier limits

The bucket is the one piece of infrastructure created manually (a deliberate bootstrapping choice — you need *somewhere* to store state before Terraform can manage anything).

## What it provisions

- `e2-micro` Compute Engine instance (Debian 12, 30GB standard disk) — free tier eligible in `us-west1`
- Buildkite agent installed and registered via startup script
- Docker installed for containerized build steps
- Agent tags (`queue=gcp,cloud=gcp,os=linux,arch=amd64`) for pipeline targeting
- SSH firewall rule (restrict via `ssh_source_ranges` or disable entirely)

## One-time setup

These steps are done once before the automated workflow takes over.

### 1. GCP service account

Create a service account with the minimum permissions needed for Terraform to manage this infrastructure:

```bash
export PROJECT_ID=your-gcp-project-id
export SA_NAME=buildkite-tf

# Create the service account
gcloud iam service-accounts create $SA_NAME \
  --display-name="Buildkite Terraform" \
  --project=$PROJECT_ID

# Grant minimum required roles
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$SA_NAME@$PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/compute.instanceAdmin.v1"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$SA_NAME@$PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/compute.securityAdmin"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$SA_NAME@$PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/storage.objectAdmin"

# Export a key — this goes into GitHub secrets
gcloud iam service-accounts keys create key.json \
  --iam-account=$SA_NAME@$PROJECT_ID.iam.gserviceaccount.com
```

> **Delete `key.json` locally after adding it to GitHub secrets.**

### 2. GCS bucket for Terraform state

```bash
gcloud storage buckets create gs://$PROJECT_ID-tfstate \
  --location=us-west1 \
  --project=$PROJECT_ID

# Enable versioning so state history is recoverable
gcloud storage buckets update gs://$PROJECT_ID-tfstate \
  --versioning
```

Then update `backend.tf` to replace `buildkite-infra-490603` with your actual project ID.

### 3. GitHub secrets

In this repo → Settings → Secrets and variables → Actions, add:

| Secret | Value |
|--------|-------|
| `GOOGLE_CREDENTIALS` | Full contents of `key.json` |
| `BUILDKITE_AGENT_TOKEN` | From Buildkite UI → Agents → New Agent |
| `BUILDKITE_SSH_PRIVATE_KEY` | Private SSH key for the agent to clone repos (e.g. `~/.ssh/id_ed25519`) |

### 4. Buildkite agent token

- Create a [Buildkite account](https://buildkite.com) (free for open source)
- Go to Agents → New Agent → copy the token
- Add to GitHub secrets as `BUILDKITE_AGENT_TOKEN`

## Workflow

| Event | What happens |
|-------|-------------|
| PR opened/updated | `terraform plan` runs, output posted as PR comment |
| PR merged to main | `terraform apply` runs automatically |

The plan-in-PR pattern means infrastructure changes go through code review before they're applied — the same discipline you'd apply to application code.

## Targeting this agent from pipelines

The agent registers with `queue=gcp,cloud=gcp,os=linux,arch=amd64`. Use these tags in `.buildkite/pipeline.yml` to route jobs to this agent:

```yaml
steps:
  - label: "build"
    command: "make build"
    agents:
      cloud: gcp
```

## Scaling up: spot instances

The `e2-micro` free tier is enough for light workloads, but resource-constrained for heavier pipelines (large test suites, Docker builds, TypeScript compilation). The next step is a **spot (preemptible) VM** — same GCP infrastructure, ~80% cheaper than on-demand, and a significant jump in available hardware.

### Why spot works well for CI agents

CI agents are stateless and interruptible by design. A Buildkite agent that gets preempted simply disconnects; Buildkite automatically re-queues the job and the next available agent picks it up. There's no data loss and no manual intervention needed. This makes CI one of the best use cases for spot pricing.

### Recommended spot configuration

```hcl
# In variables.tf, update the defaults:
variable "machine_type" {
  default = "e2-medium"   # 2 vCPU, 4GB RAM — comfortable for most CI workloads
}
```

Add a `scheduling` block to the instance in `main.tf`:

```hcl
resource "google_compute_instance" "agent" {
  # ... existing config ...

  scheduling {
    preemptible         = true
    automatic_restart   = false   # required for preemptible instances
    on_host_maintenance = "TERMINATE"
    provisioning_model  = "SPOT"
  }
}
```

### Cost comparison (us-west1)

| Instance | Type | vCPU | RAM | Monthly cost |
|----------|------|------|-----|-------------|
| `e2-micro` | Free tier | 1 shared | 1 GB | $0 |
| `e2-micro` | On-demand | 1 shared | 1 GB | ~$6 |
| `e2-medium` | On-demand | 2 shared | 4 GB | ~$27 |
| `e2-medium` | Spot | 2 shared | 4 GB | ~$5 |
| `e2-standard-4` | Spot | 4 | 16 GB | ~$15 |

A spot `e2-medium` at ~$5/month is the recommended next step — 4x the RAM and 2x the CPU for less than a coffee.

### Agent restart on preemption

GCP sends a 30-second preemption notice before terminating a spot instance. To automatically re-provision after preemption, add a startup script that re-registers the agent on boot (already handled by this repo's `startup.sh`). You can also add a GCP instance group to auto-replace terminated spot instances:

```hcl
resource "google_compute_instance_group_manager" "agents" {
  name = "buildkite-agents"
  zone = var.zone

  base_instance_name = "buildkite-agent"
  target_size        = 1

  version {
    instance_template = google_compute_instance_template.agent.id
  }
}
```

This is the pattern used in production CI fleets — a managed instance group maintains the desired number of spot agents, automatically replacing any that are preempted.

## Teardown

To destroy the instance:

```bash
terraform destroy
```

Or merge a PR that removes the resources — the GHA workflow will apply the destruction. The GCS state bucket and service account are not managed by this Terraform config and must be cleaned up manually if desired.

## Checking agent logs

After apply, Terraform outputs a command to tail agent logs:

```bash
gcloud compute ssh buildkite-agent --zone us-west1-a --project YOUR_PROJECT \
  --command 'journalctl -u buildkite-agent -f'
```

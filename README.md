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

**GHA manages infrastructure, Buildkite runs builds.** Infrastructure lifecycle (provision/update/destroy) is infrequent and benefits from PR review + plan-before-apply. Build workloads are frequent and need Buildkite features like dynamic pipelines and annotations. This also avoids a circularity: Buildkite can't provision itself.

**GCS for Terraform state** — consistent across GHA runs, supports state locking, and fits within the free tier. The bucket is the one piece created manually (a bootstrapping necessity).

## What it provisions

- `e2-micro` Compute Engine instance (Debian 12, 30GB standard disk) — free tier eligible in `us-west1`
- Buildkite agent installed and registered via startup script
- Docker, Node.js, Go, and `gotestsum` pre-installed for pipeline use
- Agent tags (`queue=gcp,cloud=gcp,os=linux,arch=amd64`) for pipeline targeting
- SSH firewall rule (restrict via `ssh_source_ranges` or disable entirely)

## One-time setup

### 1. GCP service account

```bash
export PROJECT_ID=your-gcp-project-id
export SA_NAME=buildkite-tf

gcloud iam service-accounts create $SA_NAME \
  --display-name="Buildkite Terraform" \
  --project=$PROJECT_ID

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$SA_NAME@$PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/compute.instanceAdmin.v1"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$SA_NAME@$PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/compute.securityAdmin"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$SA_NAME@$PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/storage.objectAdmin"

# Export key — add to GitHub secrets, then delete locally
gcloud iam service-accounts keys create key.json \
  --iam-account=$SA_NAME@$PROJECT_ID.iam.gserviceaccount.com
```

### 2. GCS bucket for Terraform state

```bash
gcloud storage buckets create gs://$PROJECT_ID-tfstate \
  --location=us-west1 --project=$PROJECT_ID

gcloud storage buckets update gs://$PROJECT_ID-tfstate --versioning
```

Update `backend.tf` to replace `buildkite-infra-490603` with your project ID.

### 3. GitHub secrets

| Secret | Value |
|--------|-------|
| `GOOGLE_CREDENTIALS` | Full contents of `key.json` |
| `BUILDKITE_AGENT_TOKEN` | From Buildkite UI → Agents → New Agent |
| `BUILDKITE_SSH_PRIVATE_KEY` | Private SSH key for the agent to clone repos |

## Workflow

| Event | What happens |
|-------|-------------|
| PR opened/updated | `terraform plan` runs, output posted as PR comment |
| PR merged to main | `terraform apply` runs automatically |

## Targeting this agent from pipelines

```yaml
steps:
  - label: "build"
    command: "make build"
    agents:
      queue: gcp
```

## Scaling up

The `e2-micro` free tier is enough for light workloads. For heavier pipelines, a spot `e2-medium` (~$5/month) gives 4x the RAM and 2x the CPU:

| Instance | Type | vCPU | RAM | Monthly |
|----------|------|------|-----|---------|
| `e2-micro` | Free tier | 1 shared | 1 GB | $0 |
| `e2-medium` | Spot | 2 shared | 4 GB | ~$5 |
| `e2-standard-4` | Spot | 4 | 16 GB | ~$15 |

CI agents are stateless and interruptible by design — a preempted agent disconnects, Buildkite re-queues the job, and the next agent picks it up.

## Teardown

```bash
terraform destroy
```

Or merge a PR removing the resources — GHA applies the destruction. The GCS bucket and service account are not managed by this config and must be cleaned up manually.

## Checking agent logs

```bash
gcloud compute ssh buildkite-agent --zone us-west1-a --project YOUR_PROJECT \
  --command 'journalctl -u buildkite-agent -f'
```

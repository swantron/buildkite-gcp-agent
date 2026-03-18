variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region (must be us-central1, us-west1, or us-east1 for free tier e2-micro)"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "GCP zone"
  type        = string
  default     = "us-central1-a"
}

variable "buildkite_agent_token" {
  description = "Buildkite agent registration token (from Agents > New Agent in Buildkite UI)"
  type        = string
  sensitive   = true
}

variable "agent_name" {
  description = "Name for the Buildkite agent and GCP instance"
  type        = string
  default     = "buildkite-agent"
}

variable "ssh_source_ranges" {
  description = "CIDR ranges allowed to SSH into the instance. Set to [] to disable SSH access."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

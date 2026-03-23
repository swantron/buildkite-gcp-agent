variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region (must be us-central1, us-west1, or us-east1 for free tier e2-micro)"
  type        = string
  default     = "us-west1"
}

variable "zone" {
  description = "GCP zone"
  type        = string
  default     = "us-west1-a"
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

variable "machine_type" {
  description = "GCP machine type for the agent instance (e2-micro is free tier eligible in us-central1/us-west1/us-east1)"
  type        = string
  default     = "e2-micro"
}

variable "buildkite_ssh_private_key" {
  description = "Private SSH key for the buildkite-agent user to clone from GitHub"
  type        = string
  sensitive   = true
}

variable "ssh_source_ranges" {
  description = "CIDR ranges allowed to SSH into the instance. Set to [] to disable SSH access."
  type        = list(string)
  default     = []
}

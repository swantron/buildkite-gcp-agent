terraform {
  required_version = ">= 1.5"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# Replaced whenever startup.sh changes so the new script actually runs on boot.
resource "terraform_data" "startup_script_hash" {
  input = sha256(templatefile("${path.module}/startup.sh", {
    agent_token     = var.buildkite_agent_token
    ssh_private_key = var.buildkite_ssh_private_key
  }))
}

# Free tier: e2-micro in us-central1/us-west1/us-east1
resource "google_compute_instance" "agent" {
  name         = var.agent_name
  machine_type = var.machine_type
  zone         = var.zone

  tags = ["buildkite-agent"]

  labels = {
    managed-by = "terraform"
    purpose    = "buildkite-agent"
  }

  boot_disk {
    initialize_params {
      # Free tier: 30GB standard persistent disk
      image = "debian-cloud/debian-12"
      size  = 30
      type  = "pd-standard"
    }
  }

  network_interface {
    network = "default"
    access_config {} # Ephemeral public IP — required for outbound internet access
  }

  metadata = {
    startup-script = templatefile("${path.module}/startup.sh", {
      agent_token     = var.buildkite_agent_token
      ssh_private_key = var.buildkite_ssh_private_key
    })
  }

  # Allow the instance to stop/start without destroying (useful for cost management)
  allow_stopping_for_update = true

  lifecycle {
    replace_triggered_by = [terraform_data.startup_script_hash]
  }
}

# SSH access (optional — restrict ssh_source_ranges in tfvars to lock down)
resource "google_compute_firewall" "ssh" {
  count   = length(var.ssh_source_ranges) > 0 ? 1 : 0
  name    = "${var.agent_name}-allow-ssh"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = var.ssh_source_ranges
  target_tags   = ["buildkite-agent"]
}

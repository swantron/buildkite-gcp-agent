output "instance_name" {
  description = "GCP instance name"
  value       = google_compute_instance.agent.name
}

output "external_ip" {
  description = "Public IP address of the agent instance"
  value       = google_compute_instance.agent.network_interface[0].access_config[0].nat_ip
}

output "ssh_command" {
  description = "SSH command to connect to the instance"
  value       = "gcloud compute ssh ${google_compute_instance.agent.name} --zone ${var.zone} --project ${var.project_id}"
}

output "agent_logs" {
  description = "Command to tail Buildkite agent logs on the instance"
  value       = "gcloud compute ssh ${google_compute_instance.agent.name} --zone ${var.zone} --project ${var.project_id} --command 'journalctl -u buildkite-agent -f'"
}

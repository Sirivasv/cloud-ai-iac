output "llama_node_external_ip" {
  description = "The public IP address of the Llama node"
  value       = google_compute_instance.g4_llama_dev_team.network_interface[0].access_config[0].nat_ip
}

output "api_endpoint" {
  value = "http://${google_compute_instance.g4_llama_dev_team.network_interface[0].access_config[0].nat_ip}:8080/v1/chat/completions"
}

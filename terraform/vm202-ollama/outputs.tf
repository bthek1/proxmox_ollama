output "vm_id" {
  description = "Proxmox container ID"
  value       = proxmox_virtual_environment_container.ollama_202.vm_id
}

output "vm_name" {
  description = "Container hostname"
  value       = var.vm_name
}

output "ip_address" {
  description = "Static IP of container 202"
  value       = var.ip_address
}

output "ssh_command" {
  description = "SSH command to connect to container 202"
  value       = "ssh ubuntu@${split("/", var.ip_address)[0]}"
}

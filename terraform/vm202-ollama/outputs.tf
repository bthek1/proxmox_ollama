output "vm_id" {
  description = "Proxmox VM ID"
  value       = proxmox_virtual_environment_vm.ollama_202.vm_id
}

output "vm_name" {
  description = "VM hostname"
  value       = proxmox_virtual_environment_vm.ollama_202.name
}

output "ip_address" {
  description = "Static IP of VM 202"
  value       = var.ip_address
}

output "ssh_command" {
  description = "SSH command to connect to VM 202"
  value       = "ssh ubuntu@${split("/", var.ip_address)[0]}"
}

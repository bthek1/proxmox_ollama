variable "proxmox_node" {
  description = "Proxmox node name to create the VM on"
  type        = string
  default     = "pve"
}

variable "vm_id" {
  description = "Proxmox VM ID"
  type        = number
  default     = 202
}

variable "vm_name" {
  description = "VM hostname"
  type        = string
  default     = "ollama-202"
}

variable "template_id" {
  description = "VM ID of the cloud-init Ubuntu template to clone from"
  type        = number
}

variable "cores" {
  description = "Number of vCPU cores"
  type        = number
  default     = 8
}

variable "memory_mb" {
  description = "RAM in MB"
  type        = number
  default     = 16384 # 16 GB
}

variable "disk_size" {
  description = "Primary disk size in GB"
  type        = number
  default     = 80
}

variable "datastore" {
  description = "Proxmox storage pool for the disk"
  type        = string
  default     = "local-lvm"
}

variable "ip_address" {
  description = "Static IPv4 address with prefix (CIDR)"
  type        = string
  default     = "192.168.2.202/24"
}

variable "gateway" {
  description = "Default gateway"
  type        = string
  default     = "192.168.2.1"
}

variable "dns_servers" {
  description = "DNS servers"
  type        = list(string)
  default     = ["1.1.1.1", "8.8.8.8"]
}

variable "ssh_public_key" {
  description = "SSH public key to inject via cloud-init"
  type        = string
}

variable "gpu_pci_id" {
  description = "PCI device ID of the RTX 3060 on the Proxmox host (e.g. '0000:01:00') — used by `just gpu-passthrough` post-apply"
  type        = string
  default     = "0000:01:00"
}

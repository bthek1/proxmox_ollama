resource "proxmox_virtual_environment_vm" "ollama_202" {
  node_name = var.proxmox_node
  vm_id     = var.vm_id
  name      = var.vm_name

  on_boot  = true
  started  = true

  # Clone from Ubuntu 24.04 cloud-init template
  clone {
    vm_id = var.template_id
    full  = true
  }

  cpu {
    cores = var.cores
    type  = "host" # expose host CPU flags (AVX2 etc.) — required for some LLM kernels
  }

  memory {
    dedicated = var.memory_mb
  }

  # Primary OS disk
  disk {
    datastore_id = var.datastore
    size         = var.disk_size
    interface    = "virtio0"
    discard      = "on"
    ssd          = true
  }

  # q35 machine type required for PCIe passthrough
  # GPU passthrough (hostpci0) is added post-apply via SSH — see justfile `just gpu-passthrough`
  machine = "q35"

  network_device {
    bridge = "vmbr0"
    model  = "virtio"
  }

  # cloud-init: static IP + SSH key
  initialization {
    ip_config {
      ipv4 {
        address = var.ip_address
        gateway = var.gateway
      }
    }

    dns {
      servers = var.dns_servers
    }

    user_account {
      username = "ubuntu"
      keys     = [var.ssh_public_key]
    }
  }

  # Boot from disk, not network
  boot_order = ["virtio0"]
}

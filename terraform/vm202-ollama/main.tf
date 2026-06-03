resource "proxmox_virtual_environment_container" "ollama_202" {
  node_name    = var.proxmox_node
  vm_id        = var.vm_id
  description  = "Ollama LLM — RTX 3060 GPU passthrough"
  started      = true
  unprivileged = false # privileged: required for GPU device node access

  operating_system {
    template_file_id = var.template_file_id
    type             = "ubuntu"
  }

  features {
    nesting = true # required for systemd inside the container
  }

  cpu {
    cores = var.cores
  }

  memory {
    dedicated = var.memory_mb
  }

  disk {
    datastore_id = var.datastore
    size         = var.disk_size
  }

  network_interface {
    name   = "eth0"
    bridge = "vmbr0"
  }

  initialization {
    hostname = var.vm_name

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
      keys = [var.ssh_public_key]
    }
  }
}

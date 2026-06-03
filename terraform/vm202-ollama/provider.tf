provider "proxmox" {
  # Set via environment variables:
  #   PROXMOX_VE_ENDPOINT  = "https://<proxmox-host>:8006/"
  #
  # Option A — API token (limited: cannot set hostpci on unmapped devices):
  #   PROXMOX_VE_API_TOKEN = "root@pam!terraform=<secret>"
  #
  # Option B — root username + password (required for PCIe passthrough):
  #   PROXMOX_VE_USERNAME = "root@pam"
  #   PROXMOX_VE_PASSWORD = "<root-password>"
  insecure = true # allow self-signed Proxmox TLS cert
}

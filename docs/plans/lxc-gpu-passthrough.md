# Plan: Ollama on LXC with GPU Passthrough

**Container ID:** 202  
**IP:** `192.168.2.202`  
**GPU:** NVIDIA GeForce RTX 3060 (`01:00.0`) — driver `595.71.05` on Proxmox host  
**Proxmox node:** `bthek1` (`192.168.2.70`), kernel `7.0.2-2-pve`  
**Template:** `local:vztmpl/ubuntu-24.04-standard_24.04-2_amd64.tar.zst` (already on host)

---

## How LXC GPU Passthrough Works

Unlike VM PCIe passthrough (which hands the hardware exclusively to the guest), LXC GPU passthrough **shares** the host kernel driver with the container:

```
Proxmox host
├── NVIDIA kernel module (595.71.05) ← loaded once, shared
├── /dev/nvidia0         (major 195)
├── /dev/nvidiactl       (major 195)
├── /dev/nvidia-uvm      (major 504)
├── /dev/nvidia-uvm-tools(major 504)
├── /dev/nvidia-modeset  (major 195)
└── LXC container 202
    ├── /dev/nvidia0  ← bind-mounted from host
    ├── /dev/nvidiactl
    ├── /dev/nvidia-uvm
    ├── nvidia userspace libs (same version: 595.71.05)
    └── Ollama → CUDA → /dev/nvidia0 → RTX 3060
```

**Requirements:**
- Container must be **privileged** (unprivileged containers cannot access device nodes)
- NVIDIA userspace libraries inside the container must match the host driver version (`595.71.05`)
- cgroup device allowlist must permit the device major numbers
- `features { nesting = true }` for systemd to work inside the container

---

## Phase 1 — Terraform: Create LXC Container 202

### Resource used
`proxmox_virtual_environment_container` (bpg/proxmox provider)

### Key settings

| Setting | Value | Reason |
|---|---|---|
| `unprivileged = false` | privileged | required for device node access |
| `features.nesting = true` | enabled | allows systemd inside container |
| Template | `ubuntu-24.04-standard_24.04-2_amd64.tar.zst` | already on host |
| Static IP | `192.168.2.202/24` | fixed address for Ansible + services |
| SSH key | `~/.ssh/id_ed25519.pub` | injected at creation |
| Disk | 80 GB on `local-lvm` | models need space |
| Memory | 16 384 MB | VRAM is 12 GB; system RAM buffers |
| CPU | 8 cores | |

### Files to rewrite

```
terraform/vm202-ollama/
├── versions.tf      — unchanged (bpg/proxmox ~> 0.75)
├── provider.tf      — unchanged (API token is fine for LXC)
├── variables.tf     — swap VM-specific vars for LXC vars
├── main.tf          — replace proxmox_virtual_environment_vm
│                      with proxmox_virtual_environment_container
├── outputs.tf       — update resource reference
└── terraform.tfvars — update template_file_id, remove gpu_pci_id
```

### `main.tf` container resource (target)

```hcl
resource "proxmox_virtual_environment_container" "ollama_202" {
  node_name    = var.proxmox_node
  vm_id        = var.vm_id
  description  = "Ollama LLM — RTX 3060 GPU passthrough"
  started      = true
  unprivileged = false   # privileged: required for GPU device access

  operating_system {
    template_file_id = var.template_file_id
    type             = "ubuntu"
  }

  features {
    nesting = true       # needed for systemd
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
```

### Tasks

- [ ] Rewrite `variables.tf` — replace `template_id`/`gpu_pci_id` with `template_file_id`
- [ ] Rewrite `main.tf` — `proxmox_virtual_environment_container` resource
- [ ] Update `outputs.tf` — fix resource name reference
- [ ] Update `terraform.tfvars` — set `template_file_id`, remove gpu vars
- [ ] Update `terraform.tfvars.example` likewise
- [ ] `just tf-init && just tf-plan` — verify plan
- [ ] `just provision` — create container 202

---

## Phase 2 — GPU Passthrough: Patch LXC Config

Terraform **cannot** add raw LXC config lines. After `just provision`, patch `/etc/pve/lxc/202.conf` on the Proxmox host via SSH.

### Lines to append to `/etc/pve/lxc/202.conf`

```ini
# NVIDIA RTX 3060 GPU passthrough
# Major 195 = /dev/nvidia*, /dev/nvidiactl, /dev/nvidia-modeset
lxc.cgroup2.devices.allow: c 195:* rwm
# Major 504 = /dev/nvidia-uvm, /dev/nvidia-uvm-tools
lxc.cgroup2.devices.allow: c 504:* rwm
# Major 508 = /dev/nvidia-caps/*
lxc.cgroup2.devices.allow: c 508:* rwm

lxc.mount.entry: /dev/nvidia0 dev/nvidia0 none bind,optional,create=file
lxc.mount.entry: /dev/nvidiactl dev/nvidiactl none bind,optional,create=file
lxc.mount.entry: /dev/nvidia-modeset dev/nvidia-modeset none bind,optional,create=file
lxc.mount.entry: /dev/nvidia-uvm dev/nvidia-uvm none bind,optional,create=file
lxc.mount.entry: /dev/nvidia-uvm-tools dev/nvidia-uvm-tools none bind,optional,create=file
```

### `just gpu-passthrough` command (in justfile)

```bash
ssh proxmox "echo 3719 | sudo -Sp '' tee -a /etc/pve/lxc/202.conf" << 'EOF'
# NVIDIA RTX 3060 GPU passthrough
lxc.cgroup2.devices.allow: c 195:* rwm
lxc.cgroup2.devices.allow: c 504:* rwm
lxc.cgroup2.devices.allow: c 508:* rwm
lxc.mount.entry: /dev/nvidia0 dev/nvidia0 none bind,optional,create=file
lxc.mount.entry: /dev/nvidiactl dev/nvidiactl none bind,optional,create=file
lxc.mount.entry: /dev/nvidia-modeset dev/nvidia-modeset none bind,optional,create=file
lxc.mount.entry: /dev/nvidia-uvm dev/nvidia-uvm none bind,optional,create=file
lxc.mount.entry: /dev/nvidia-uvm-tools dev/nvidia-uvm-tools none bind,optional,create=file
EOF
# Then restart the container so the mounts take effect
ssh proxmox "echo 3719 | sudo -Sp '' pct stop 202 && echo 3719 | sudo -Sp '' pct start 202"
```

### Tasks

- [ ] Add `just gpu-passthrough` to justfile
- [ ] Run `just gpu-passthrough` after provision
- [ ] Verify device nodes inside container: `pct exec 202 -- ls -la /dev/nvidia*`

---

## Phase 3 — Ansible: Install NVIDIA Libs + Ollama

### What changes vs the VM plan

| Aspect | VM plan | LXC plan |
|---|---|---|
| `nvidia_drivers` role | Install kernel driver + CUDA | **Removed** — driver lives on host |
| NVIDIA in container | Full driver | userspace libs only (same version as host) |
| `ollama` role | unchanged | unchanged |
| Reboot handler | needed after driver install | **not needed** |

### `site.yml` (LXC version)

```yaml
- name: Configure Ollama LXC 202
  hosts: ollama_hosts
  become: true
  roles:
    - nvidia_userspace   # install matching libs (595.71.05), no kernel module
    - ollama             # install binary, systemd, pull model
```

### `nvidia_userspace` role tasks

1. Add NVIDIA apt repo (Ubuntu 24.04)
2. Install `nvidia-utils-open-575` or closest matching `nvidia-utils-XXX` package for driver `595.71.05`
3. Install `libnvidia-compute-595` (CUDA runtime libs)
4. Verify: `nvidia-smi` returns RTX 3060 inside the container

> The userspace library version must match the host kernel module version (`595.71.05`).
> Package naming on Ubuntu: `nvidia-utils-open-<major>` and `libnvidia-compute-<major>`.
> Confirm exact package names after the container is up.

### `ollama` role — no changes needed

Ollama's install script detects CUDA automatically via `/dev/nvidia*`. The existing role works as-is.

### Tasks

- [ ] Rename `ansible/roles/nvidia_drivers` → `ansible/roles/nvidia_userspace`
- [ ] Rewrite `nvidia_userspace/tasks/main.yml` — apt install libs only, no kernel module, no reboot
- [ ] Remove reboot handler from `nvidia_userspace/handlers/main.yml`
- [ ] Update `ansible/site.yml` — use `nvidia_userspace` role
- [ ] Update `ansible/group_vars/ollama_hosts/vars.yml` — set `nvidia_driver_version: "595"`
- [ ] Run `just deploy` — install libs + Ollama
- [ ] Verify inside container: `nvidia-smi` and `curl http://192.168.2.202:11434/api/version`

---

## Phase 4 — Validation

```bash
# 1. Container is running
just ping                # ansible can reach 192.168.2.202

# 2. GPU visible inside container
ssh ubuntu@192.168.2.202 nvidia-smi
# → should show: NVIDIA GeForce RTX 3060, driver 595.71.05

# 3. Ollama running
curl http://192.168.2.202:11434/api/version

# 4. Model available
curl http://192.168.2.202:11434/api/tags
# → qwen2.5:3b, analysis-assistant

# 5. GPU used for inference
just status   # scripts/status.py shows GPU utilisation

# 6. Service survives restart
ssh proxmox "echo 3719 | sudo -Sp '' pct stop 202 && pct start 202"
sleep 30
curl http://192.168.2.202:11434/api/version
```

---

## Execution Order

```
Phase 1          Phase 2              Phase 3          Phase 4
Terraform   →   GPU passthrough  →   Ansible     →   Validate
Create LXC      Patch LXC config     Libs + Ollama
container       via SSH on host
```

Phase 2 must happen **before** Phase 3 — Ansible's `nvidia-smi` verification step will fail if the device nodes are not yet mounted.

---

## Known Constraints

| Constraint | Detail |
|---|---|
| Container must be privileged | `unprivileged = false` — LXC unprivileged containers cannot access character devices |
| Library version must match host driver | Host runs `595.71.05`; container must install matching userspace libs |
| Device major numbers are static on this host | `195`, `504`, `508` — confirmed from `ls -la /dev/nvidia*` |
| `just gpu-passthrough` must re-run after `terraform destroy && provision` | Terraform doesn't manage the raw LXC config lines |
| Ollama model storage | Inside the container at `/root/.ollama/models` — persists as long as the container disk exists |

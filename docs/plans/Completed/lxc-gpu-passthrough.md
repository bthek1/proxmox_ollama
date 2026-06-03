# Plan: Ollama on LXC with GPU Passthrough

> **Status: COMPLETED 2026-06-03** — all services live and validated.

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
- `lxc.apparmor.profile: unconfined` — required for Docker to manage its own AppArmor profiles

---

## Phase 1 — Create LXC Container 202

> **Actual method:** `pct create` over SSH via `just provision`.  
> `terraform apply` was attempted first but Proxmox blocks privileged container creation even for `root@pam` API tokens — this is a hard Proxmox VE security restriction. The Terraform files document the intended config but state is not managed by Terraform.

### `just provision` (actual command used)

```bash
ssh proxmox "echo 3719 | sudo -Sp '' pct create 202 \
  local:vztmpl/ubuntu-24.04-standard_24.04-2_amd64.tar.zst \
  --hostname ollama-202 \
  --memory 16384 \
  --cores 8 \
  --net0 name=eth0,bridge=vmbr0,ip=192.168.2.202/24,gw=192.168.2.1 \
  --rootfs local-lvm:80 \
  --unprivileged 0 \
  --features nesting=1 \
  --ssh-public-keys /tmp/ollama-202.pub \
  --nameserver '1.1.1.1 8.8.8.8' \
  --onboot 1"
```

### SSH user

LXC containers created from the Ubuntu template have **only `root`** — no `ubuntu` user. SSH and Ansible both connect as `root`.

### Tasks

- [x] Rewrite `variables.tf` — replace `template_id`/`gpu_pci_id` with `template_file_id`
- [x] Rewrite `main.tf` — `proxmox_virtual_environment_container` resource
- [x] Update `outputs.tf` — fix resource name reference
- [x] Update `terraform.tfvars` — set `template_file_id`, remove gpu vars
- [x] Update `terraform.tfvars.example` likewise
- [x] `just tf-plan` — verified plan
- [x] `just provision` — created container 202 via `pct create` over SSH

---

## Phase 2 — GPU Passthrough: Patch LXC Config

Config lines live in `scripts/lxc-202-gpu.conf` and are applied with:

```bash
scp scripts/lxc-202-gpu.conf proxmox:/tmp/lxc-202-gpu.conf
ssh proxmox "echo 3719 | sudo -Sp '' bash -c \
  'cat /tmp/lxc-202-gpu.conf >> /etc/pve/lxc/202.conf && rm /tmp/lxc-202-gpu.conf'"
ssh proxmox "echo 3719 | sudo -Sp '' pct stop 202 && \
  echo 3719 | sudo -Sp '' pct start 202"
```

> **Note:** `just` cannot use heredocs containing `lxc.` lines — the parser interprets the dots as recipe syntax. The config is stored in a separate file and transferred with `scp`.

### Lines appended to `/etc/pve/lxc/202.conf`

```ini
lxc.cgroup2.devices.allow: c 195:* rwm
lxc.cgroup2.devices.allow: c 504:* rwm
lxc.cgroup2.devices.allow: c 508:* rwm
lxc.mount.entry: /dev/nvidia0 dev/nvidia0 none bind,optional,create=file
lxc.mount.entry: /dev/nvidiactl dev/nvidiactl none bind,optional,create=file
lxc.mount.entry: /dev/nvidia-modeset dev/nvidia-modeset none bind,optional,create=file
lxc.mount.entry: /dev/nvidia-uvm dev/nvidia-uvm none bind,optional,create=file
lxc.mount.entry: /dev/nvidia-uvm-tools dev/nvidia-uvm-tools none bind,optional,create=file
lxc.apparmor.profile: unconfined
```

### Tasks

- [x] Config stored in `scripts/lxc-202-gpu.conf`
- [x] `just gpu-passthrough` runs `scp` + SSH append + container restart
- [x] Verified device nodes: all 5 `/dev/nvidia*` visible inside container

---

## Phase 3 — Ansible: Install NVIDIA Libs + Ollama + UIs

### What changed vs the VM plan

| Aspect | VM plan | LXC plan (actual) |
|---|---|---|
| `nvidia_drivers` role | Install kernel driver + CUDA | **Removed** — driver lives on host |
| NVIDIA in container | Full driver | `nvidia_userspace` role: userspace libs only |
| Reboot handler | needed | not needed |
| Ollama prereqs | none extra | `zstd` must be installed first |
| Docker services | no special flags | `--security-opt apparmor=unconfined` required |
| AnythingLLM storage | `mode: 0755` | must be `mode: 0777` — container runs as non-root |

### `site.yml`

```yaml
roles:
  - nvidia_userspace   # install nvidia-utils-595 + libnvidia-compute-595
  - ollama             # install binary, systemd, pull model
  - open_webui         # Docker container, port 3000
  - anything_llm       # Docker container, port 3001
```

### Tasks

- [x] Created `ansible/roles/nvidia_userspace` — apt install libs only, no kernel module, no reboot
- [x] Updated `ansible/site.yml`
- [x] Updated `ansible/group_vars/ollama_hosts/vars.yml` — `nvidia_driver_version: "595"`, added WebUI/AnythingLLM vars
- [x] Added `zstd` prerequisite to `ollama` role
- [x] Added `--security-opt apparmor=unconfined` to both Docker service templates
- [x] Set AnythingLLM storage dir `mode: 0777`
- [x] `just deploy` — all roles applied successfully

---

## Phase 4 — Validation

```
Ollama API:      curl http://192.168.2.202:11434/api/version  → {"version":"0.30.2"}
Models:          qwen2.5:3b (1.93 GB), analysis-assistant:latest (1.93 GB), nomic-embed-text (0.27 GB)
GPU:             NVIDIA GeForce RTX 3060, driver 595.71.05, 12288 MiB VRAM
Inference:       curl /api/generate → response confirmed (GPU, done_reason: stop)
Embeddings:      POST /api/embed with nomic-embed-text → 768-dim vectors  ✓
Open WebUI:      http://192.168.2.202:3000  → HTTP 200
AnythingLLM:     http://192.168.2.202:3001  → HTTP 200
API test suite:  just test-api → all 6 sections PASS
```

---

## Execution Order

```
Phase 1          Phase 2              Phase 3          Phase 4
pct create   →   gpu-passthrough  →   Ansible     →   Validate
(via SSH)        (scp + SSH)          Libs + Ollama
                                      + UIs
```

Phase 2 must happen **before** Phase 3 — `nvidia-smi` verification will fail if device nodes aren't mounted.

---

## Known Constraints & Gotchas

| Constraint | Detail |
|---|---|
| Container must be privileged | LXC unprivileged containers cannot access character devices |
| Proxmox API token cannot create privileged containers | Even `root@pam!terraform` tokens are blocked — must use `pct create` via SSH |
| Library version must match host driver | Host runs `595.71.05`; container installs `nvidia-utils-595` + `libnvidia-compute-595` |
| `lxc.apparmor.profile: unconfined` required | Docker inside privileged LXC cannot load AppArmor profiles without this |
| Docker services need `--security-opt apparmor=unconfined` | Even with the LXC profile set to unconfined, Docker run needs the flag too |
| Ollama install script requires `zstd` | Not installed by default in the Ubuntu 24.04 LXC template |
| AnythingLLM storage needs `mode: 0777` | Container process runs as non-root and can't write to `0755` dir |
| `just gpu-passthrough` cannot use heredoc | `just` parses `lxc.*` lines as recipe syntax; config lives in `scripts/lxc-202-gpu.conf` |
| `gpu-passthrough` must re-run after destroy + provision | Terraform/pct doesn't persist the raw LXC config lines |
| Ollama model storage | At `/root/.ollama/models` inside container — persists as long as container disk exists |

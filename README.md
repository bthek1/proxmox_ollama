# proxmox-ollama

Terraform + Ansible infrastructure for running Ollama on a Proxmox LXC container with NVIDIA GPU passthrough.

**Target:** LXC 202 — `192.168.2.202` — NVIDIA GeForce RTX 3060 (12 GB VRAM)

---

## Stack

| Layer       | Tool      | Purpose                                                    |
|-------------|-----------|------------------------------------------------------------|
| Provision   | SSH + pct | Create privileged LXC container 202 on Proxmox             |
| Configure   | Ansible   | Install NVIDIA userspace libs, Ollama, Open WebUI, AnythingLLM |
| Task runner | just      | Wrap common SSH/Ansible ops                                |

> **Note:** `just provision` uses `pct create` over SSH — not `terraform apply`. Proxmox API tokens cannot create privileged containers even as `root@pam`, so Terraform is used for config documentation only.

### Services on LXC 202

| Service       | Port  | URL                              |
|---------------|-------|----------------------------------|
| Ollama API    | 11434 | `http://192.168.2.202:11434`     |
| Open WebUI    | 3000  | `http://192.168.2.202:3000`      |
| AnythingLLM   | 3001  | `http://192.168.2.202:3001`      |

---

## Quick Start

```bash
# 1. Fill in Proxmox credentials
cp terraform/vm202-ollama/secrets.auto.tfvars.example \
   terraform/vm202-ollama/secrets.auto.tfvars
# Edit secrets.auto.tfvars — set proxmox_api_token_secret

# 2. Create LXC container 202 (via pct over SSH)
just provision

# 3. Patch GPU device mounts into /etc/pve/lxc/202.conf (run once after provision)
just gpu-passthrough

# 4. Install NVIDIA libs, Ollama, Open WebUI, AnythingLLM
just deploy

# 5. Verify
just status
```

---

## Repository Layout

```
proxmox_ollama/
├── ansible/
│   ├── inventory/hosts.yml
│   ├── group_vars/ollama_hosts/
│   │   ├── vars.yml          # non-secret config (models, ports, driver version)
│   │   └── vault.yml         # secrets placeholder (not yet encrypted)
│   ├── roles/
│   │   ├── nvidia_userspace/ # installs userspace libs matching host driver 595.71.05
│   │   ├── ollama/           # Ollama binary, systemd service, model pull
│   │   ├── open_webui/       # Docker container on port 3000
│   │   └── anything_llm/     # Docker container on port 3001
│   └── site.yml
├── terraform/
│   └── vm202-ollama/
│       ├── provider.tf
│       ├── variables.tf
│       ├── main.tf           # documents intended LXC config
│       ├── outputs.tf
│       ├── secrets.auto.tfvars.example
│       └── terraform.tfvars.example
├── scripts/
│   ├── status.py             # queries Ollama API and prints status
│   └── lxc-202-gpu.conf      # LXC conf lines appended by just gpu-passthrough
├── docs/
│   ├── docker-ollama-reference.md
│   ├── proxmox-lxc-terraform-guide.md
│   └── plans/Completed/
│       ├── lxc-gpu-passthrough.md   # completed plan + lessons learned
│       └── migrate-to-terraform-ansible.md
├── justfile
└── CLAUDE.md
```

---

## Prerequisites

- Ansible >= 2.14
- `just` task runner
- SSH key at `~/.ssh/id_ed25519` (injected into container root at provision time)
- SSH alias `proxmox` → `ben@192.168.2.70` configured in `~/.ssh/config`

---

## Common Commands

```bash
just provision          # create LXC container 202 via pct over SSH
just gpu-passthrough    # append GPU + AppArmor config to /etc/pve/lxc/202.conf, restart container
just deploy             # run ansible-playbook site.yml (no vault password needed)
just deploy-check       # dry run (--check --diff)
just status             # query Ollama API — version, models, GPU
just models             # list downloaded models and sizes
just pull mistral       # pull a model by name
just logs               # tail Ollama systemd logs
just gpu                # nvidia-smi on container 202
just ssh                # SSH into container 202 as root
just ct-stop            # stop LXC container 202
just ct-start           # start LXC container 202
```

---

## Credentials

**Proxmox API token** (`secrets.auto.tfvars`, gitignored):
```hcl
proxmox_api_token_id     = "root@pam!terraform"
proxmox_api_token_secret = "..."
```
Token must belong to `root@pam` — other users are blocked from privileged container operations.

**Ansible secrets** (`vault.yml`): not currently encrypted. WebUI admin credentials are hardcoded in `group_vars/ollama_hosts/vars.yml` and should be moved to a proper vault before exposing services externally.

---

## Known Gotchas

| Issue | Fix applied |
|---|---|
| Proxmox API token cannot create privileged containers | `just provision` uses `pct create` via SSH instead of `terraform apply` |
| Docker blocked by AppArmor inside privileged LXC | `lxc.apparmor.profile: unconfined` in LXC conf + `--security-opt apparmor=unconfined` in each `docker run` |
| Ollama install script needs `zstd` | Added as apt prerequisite in the `ollama` role |
| AnythingLLM SQLite can't write to mounted volume | Storage dir created with `mode: 0777` |
| `just` heredocs can't contain `lxc.*` lines | GPU config lives in `scripts/lxc-202-gpu.conf`, applied via `scp` |

---

## Reference

- [LXC GPU Passthrough Plan](docs/plans/Completed/lxc-gpu-passthrough.md) — completed, full lessons learned
- [Proxmox LXC Terraform Guide](docs/proxmox-lxc-terraform-guide.md)
- [Docker Ollama Reference](docs/docker-ollama-reference.md) — archived Docker knowledge

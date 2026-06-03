# Migration Plan: Docker → Terraform + Ansible (Machine 202)

**Target machine:** `192.168.2.202` (Proxmox VM 202)  
**GPU:** NVIDIA GeForce RTX 3060  
**Started:** 2026-06-03  
**Status:** Phases 1–5 complete — ready for deployment

---

## Overview

Migrate Ollama from a Docker Compose deployment on the current host to a Terraform-provisioned + Ansible-configured VM on Proxmox (`192.168.2.202`). Preserve all Docker knowledge in `docs/` before removing Docker code.

---

## Phase 1 — Archive Docker Knowledge ✅ DONE

**Goal:** Capture everything learned from the Docker deployment into `docs/docker-ollama-reference.md` before any code is deleted.

### Tasks

- [x] Create `docs/docker-ollama-reference.md` containing:
  - Full annotated `docker-compose.yml` with explanation of every field
  - All environment variables and their purpose (`OLLAMA_NUM_PARALLEL`, `OLLAMA_MAX_LOADED_MODELS`, `OLLAMA_FLASH_ATTENTION`, `OLLAMA_KEEP_ALIVE`, `OLLAMA_ORIGINS`)
  - NVIDIA CDI passthrough (`nvidia.com/gpu=all`) explanation and requirements
  - Open WebUI service config and env vars (`WEBUI_SECRET_KEY`, `SCOPED_MODEL_PERMISSIONS`, etc.)
  - AnythingLLM service config and env vars
  - `ollama-init` sidecar pattern (pull model + create custom model on first boot)
  - `Modelfile` content and purpose (`analysis-assistant` built on `qwen2.5:3b`)
  - Healthcheck patterns used (`ollama list`, `curl /health`)
  - Bind mount strategy: host `~/ollama_doc/models/` → container `/root/.ollama/models`
  - Named volume strategy for Open WebUI and AnythingLLM data
  - Network topology (`ollama-network` bridge, port bindings per service)
  - All `just` commands with descriptions
  - Python tooling: `ollama`, `llm`, `llm-ollama` packages, `uv` workflow
  - `scripts/status.py` and `main.py` purpose and usage
  - REST API examples (chat, generate)
  - Python API examples (streaming chat, list models)
  - Recommended models table with sizes
  - `.env` variables for Open WebUI credentials

---

## Phase 2 — Clean the Repository ✅ DONE

**Goal:** Remove all Docker-specific code, leaving only docs, the new IaC structure, and shared Python utilities if still useful.

### Files deleted

| File / Dir | Done |
|---|---|
| `docker-compose.yml` | ✅ |
| `Modelfile` | ✅ (templated in Ansible) |
| `justfile` | ✅ (replaced with Ansible-aware version) |
| `phase6-setup.sh` | ✅ |
| `docker-openwebui-setup.md` | ✅ (superseded by `docs/docker-ollama-reference.md`) |
| `.env` | ✅ (secrets now in Ansible vault) |
| `.envrc` | ✅ |
| `uv.lock` | ✅ |
| `pyproject.toml` | ✅ |
| `main.py` | ✅ |

### Files moved / updated

| File | Action | Done |
|---|---|---|
| `CLAUDE.md` | Updated for IaC structure | ✅ |
| `README.md` | Rewritten for Terraform + Ansible | ✅ |
| `PROXMOX_LXC_TERRAFORM_GUIDE.md` | Moved → `docs/proxmox-lxc-terraform-guide.md` | ✅ |
| `django-drf-react-rag-ollama.md` | Moved → `docs/` | ✅ |
| `scripts/status.py` | Rewritten — queries `192.168.2.202:11434` directly | ✅ |

---

## Phase 3 — Terraform: Provision VM 202 ✅ DONE (code written)

**Goal:** Use Terraform with the `bpg/proxmox` provider to create or import VM 202 on Proxmox.

> If VM 202 already exists (bare Ubuntu), use Terraform to import and manage it going forward. If it does not exist, create it from a cloud-init template.

### Files written

```
terraform/vm202-ollama/
├── versions.tf          ✅
├── provider.tf          ✅
├── variables.tf         ✅
├── main.tf              ✅  (VM resource with cloud-init + GPU passthrough)
├── outputs.tf           ✅
└── terraform.tfvars.example  ✅
```

### Key Terraform decisions

| Decision | Choice | Notes |
|---|---|---|
| Resource type | `proxmox_virtual_environment_vm` | bpg/proxmox `qemu` resource |
| OS | Ubuntu 24.04 (cloud-init image) | Pre-downloaded on Proxmox node |
| GPU passthrough | PCIe passthrough for RTX 3060 | Requires IOMMU enabled on Proxmox host |
| Static IP | `192.168.2.202/24` | Set via cloud-init network config |
| SSH key | `~/.ssh/id_ed25519.pub` | Injected via cloud-init |
| Disk | VirtIO, ≥ 50 GB | Model storage is large |
| Memory | ≥ 16 GB | RTX 3060 has 12 GB VRAM; system RAM buffers |
| CPU | ≥ 4 cores | host CPU type for AVX2 support |

### Still to do (run time)

- [ ] Set env vars: `PROXMOX_VE_ENDPOINT`, `PROXMOX_VE_API_TOKEN`
- [ ] Copy `terraform.tfvars.example` → `terraform.tfvars` and fill in values
- [ ] Run `just tf-init` then `just tf-plan` — review before apply
- [ ] Run `just provision` to create / import VM 202

### Environment variables required

```bash
export PROXMOX_VE_ENDPOINT="https://<proxmox-host>:8006/"
export PROXMOX_VE_API_TOKEN="root@pam!terraform=<secret>"
```

---

## Phase 4 — Ansible: Configure Machine 202 ✅ DONE (code written)

**Goal:** Use Ansible to install NVIDIA drivers, CUDA, Ollama (native binary), Open WebUI, and AnythingLLM on VM 202.

### Files written

```
ansible/
├── inventory/hosts.yml                          ✅
├── group_vars/ollama_hosts/vars.yml             ✅
├── group_vars/ollama_hosts/vault.yml            ✅ (encrypted — fill in secrets)
├── roles/nvidia_drivers/tasks/main.yml          ✅
├── roles/nvidia_drivers/handlers/main.yml       ✅
├── roles/ollama/tasks/main.yml                  ✅
├── roles/ollama/handlers/main.yml               ✅
├── roles/ollama/templates/Modelfile.j2          ✅
├── roles/ollama/templates/ollama-env.conf.j2    ✅
├── roles/open_webui/tasks/main.yml              ✅
├── roles/open_webui/handlers/main.yml           ✅
├── roles/open_webui/templates/open-webui.service.j2  ✅
├── roles/anything_llm/tasks/main.yml            ✅
├── roles/anything_llm/handlers/main.yml         ✅
├── roles/anything_llm/templates/anything-llm.service.j2  ✅
└── site.yml                                     ✅
```

### Role summary

| Role | What it does |
|---|---|
| `nvidia_drivers` | Adds NVIDIA apt repo, installs driver + CUDA, reboots if needed |
| `ollama` | Installs Ollama binary, systemd service, pulls `qwen2.5:3b`, builds `analysis-assistant` |
| `open_webui` | Deploys Open WebUI container, systemd unit, port 3000 |
| `anything_llm` | Deploys AnythingLLM container, systemd unit, port 3001 |

### Still to do (run time)

- [ ] Edit vault with real secrets: `just vault-edit`
- [ ] Test connectivity: `just ping`
- [ ] Dry run: `just deploy-check`
- [ ] Apply: `just deploy`
- [ ] Verify Ollama: `curl http://192.168.2.202:11434/api/version`
- [ ] Verify GPU: `just gpu`

---

## Phase 5 — New `justfile` and Tooling ✅ DONE

**Goal:** Replace Docker-centric `justfile` with Ansible + SSH-aware commands.

### Commands available

| Command | Action |
|---|---|
| `just tf-init` | `terraform init` |
| `just tf-plan` | `terraform plan` |
| `just provision` | `terraform apply` — provision VM 202 |
| `just tf-destroy` | `terraform destroy` (destructive — confirms) |
| `just tf-output` | Show Terraform outputs |
| `just ping` | `ansible -m ping` — test SSH to VM 202 |
| `just deploy` | Full `ansible-playbook site.yml` |
| `just deploy-check` | Dry run with `--check --diff` |
| `just deploy-ollama` | Run only the `ollama` role |
| `just deploy-webui` | Run only the `open_webui` role |
| `just vault-edit` | Edit encrypted vault |
| `just ssh` | SSH into VM 202 |
| `just status` | Query Ollama API + GPU via `scripts/status.py` |
| `just models` | List downloaded models |
| `just pull <model>` | Pull a model via SSH |
| `just remove <model>` | Remove a model via SSH |
| `just gpu` | `nvidia-smi` on VM 202 |
| `just logs` | `journalctl -fu ollama` on VM 202 |
| `just restart-ollama` | Restart the Ollama systemd service |
| `just service-status` | Status of all 3 services |

### `scripts/status.py`
Rewritten to query `http://192.168.2.202:11434` directly over HTTP — no Docker dependency. Also fetches GPU stats via SSH (`nvidia-smi`).

---

## Phase 6 — Validation Checklist

Run these after `just provision` + `just deploy`:

- [ ] `just tf-output` shows VM 202 IP
- [ ] `just ping` — Ansible can reach VM 202
- [ ] `just gpu` — `nvidia-smi` shows RTX 3060 (12 GB VRAM)
- [ ] `curl http://192.168.2.202:11434/api/version` returns Ollama version
- [ ] `curl http://192.168.2.202:11434/api/tags` lists `qwen2.5:3b` and `analysis-assistant`
- [ ] `just status` shows GPU + loaded models
- [ ] Open WebUI accessible at `http://192.168.2.202:3000`
- [ ] AnythingLLM accessible at `http://192.168.2.202:3001`
- [ ] Ollama service survives reboot (`sudo reboot` then `just status`)
- [ ] Model files persist across reboots

---

## Final Repository Structure

```
proxmox_ollama/
├── ansible/
│   ├── inventory/hosts.yml
│   ├── group_vars/ollama_hosts/
│   │   ├── vars.yml
│   │   └── vault.yml
│   ├── roles/
│   │   ├── nvidia_drivers/
│   │   ├── ollama/
│   │   ├── open_webui/
│   │   └── anything_llm/
│   └── site.yml
├── terraform/
│   └── vm202-ollama/
│       ├── versions.tf
│       ├── provider.tf
│       ├── variables.tf
│       ├── main.tf
│       ├── outputs.tf
│       └── terraform.tfvars.example
├── docs/
│   ├── docker-ollama-reference.md
│   ├── proxmox-lxc-terraform-guide.md
│   ├── django-drf-react-rag-ollama.md
│   └── plans/
│       └── migrate-to-terraform-ansible.md
├── scripts/
│   └── status.py
├── justfile
├── CLAUDE.md
└── README.md
```

---

## Next Step

All code is written. To deploy:

```bash
# 1. Set Proxmox credentials
export PROXMOX_VE_ENDPOINT="https://<proxmox-host>:8006/"
export PROXMOX_VE_API_TOKEN="root@pam!terraform=<secret>"

# 2. Fill in terraform vars
cp terraform/vm202-ollama/terraform.tfvars.example terraform/vm202-ollama/terraform.tfvars
# edit terraform.tfvars

# 3. Fill in vault secrets
just vault-edit

# 4. Provision + configure
just tf-init
just tf-plan      # review before applying
just provision
just ping         # verify SSH works
just deploy-check # dry run
just deploy

# 5. Validate
just status
just gpu
```

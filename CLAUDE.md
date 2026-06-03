# proxmox-ollama — Codebase Guide

## Project Purpose

Terraform + Ansible infrastructure to deploy Ollama (local LLM inference) on **LXC container 202** (`192.168.2.202`) in Proxmox, with NVIDIA GeForce RTX 3060 GPU passthrough via LXC device sharing.

## Target Machine

| Property | Value |
|---|---|
| Container ID | 202 |
| IP | `192.168.2.202` |
| GPU | NVIDIA GeForce RTX 3060 (12 GB VRAM) — shared from Proxmox host driver `595.71.05` |
| OS | Ubuntu 24.04 (LXC, privileged) |
| SSH user | `ubuntu` |

## Services Deployed

| Service       | Port  | Notes                              |
|---------------|-------|------------------------------------|
| Ollama API    | 11434 | Native binary, systemd service     |
| Open WebUI    | 3000  | Browser chat UI                    |
| AnythingLLM   | 3001  | RAG / document chat UI             |

## Key Files

| Path | Purpose |
|---|---|
| `terraform/vm202-ollama/` | Provision LXC container 202 on Proxmox |
| `ansible/site.yml` | Main playbook — runs all roles |
| `ansible/inventory/hosts.yml` | Container 202 host entry |
| `ansible/group_vars/ollama_hosts/vars.yml` | Non-secret config |
| `ansible/group_vars/ollama_hosts/vault.yml` | Encrypted secrets |
| `ansible/roles/nvidia_userspace/` | NVIDIA userspace libs (matches host driver `595.71.05`) |
| `ansible/roles/ollama/` | Ollama binary, systemd, models |
| `ansible/roles/open_webui/` | Open WebUI deployment |
| `ansible/roles/anything_llm/` | AnythingLLM deployment |
| `justfile` | Task runner |
| `scripts/status.py` | Query Ollama API on container 202 |
| `docs/docker-ollama-reference.md` | Archived Docker knowledge |

## Common Commands

```bash
just provision          # terraform apply — create LXC container
just gpu-passthrough    # patch /etc/pve/lxc/202.conf + restart (run once after provision)
just deploy             # ansible-playbook site.yml
just status             # query http://192.168.2.202:11434
just gpu                # nvidia-smi on container 202
just ssh                # SSH into container 202
```

## Terraform

- Provider: `bpg/proxmox` ~> 0.75
- Working dir: `terraform/vm202-ollama/`
- Credentials via env vars: `PROXMOX_VE_ENDPOINT`, `PROXMOX_VE_API_TOKEN`
- Never commit `terraform.tfvars` — use `terraform.tfvars.example` as template

## Ansible

- Inventory: `ansible/inventory/hosts.yml`
- Vault: `ansible/group_vars/ollama_hosts/vault.yml`
- Run with: `ansible-playbook ansible/site.yml --ask-vault-pass`
- Roles: `nvidia_userspace` → `ollama` → `open_webui` → `anything_llm`

## Default Model

`qwen2.5:3b` — small, fits in limited VRAM scenarios. Custom model `analysis-assistant` built on top via Modelfile (see `ansible/roles/ollama/templates/Modelfile.j2`).

## Reference Docs

- [Docker Ollama Reference](docs/docker-ollama-reference.md) — original Docker setup knowledge
- [Proxmox LXC Terraform Guide](docs/proxmox-lxc-terraform-guide.md)
- [Migration Plan](docs/plans/migrate-to-terraform-ansible.md)

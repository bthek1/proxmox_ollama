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
| SSH user | `root` (LXC containers created from template have only root; no ubuntu user) |

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
| `ansible/group_vars/ollama_hosts/vault.yml` | Secrets placeholder (not currently encrypted) |
| `ansible/roles/nvidia_userspace/` | NVIDIA userspace libs (matches host driver `595.71.05`) |
| `ansible/roles/ollama/` | Ollama binary, systemd, models |
| `ansible/roles/open_webui/` | Open WebUI deployment |
| `ansible/roles/anything_llm/` | AnythingLLM deployment |
| `justfile` | Task runner |
| `scripts/test_ollama.py` | Ollama API test client (health, models, generate, stream, chat, embeddings) |
| `scripts/lxc-202-gpu.conf` | LXC config lines for GPU passthrough + AppArmor (appended by `just gpu-passthrough`) |
| `pyproject.toml` | uv project — Python deps (`ollama`, `httpx`, `rich`) |
| `docs/docker-ollama-reference.md` | Archived Docker knowledge |

## Common Commands

```bash
just provision          # create LXC container via pct over SSH (not terraform apply)
just gpu-passthrough    # patch /etc/pve/lxc/202.conf + restart (run once after provision)
just deploy             # ansible-playbook site.yml
just test-api           # run Ollama API test suite against 192.168.2.202:11434
just gpu                # nvidia-smi on container 202
just ssh                # SSH into container 202
```

## Terraform

- Provider: `bpg/proxmox` ~> 0.75
- Working dir: `terraform/vm202-ollama/`
- **`provision` does NOT use `terraform apply`** — Proxmox API tokens cannot create privileged containers even as `root@pam`. `just provision` runs `pct create` over SSH via sudo instead.
- Terraform files (`variables.tf`, `main.tf`, etc.) document the intended config; state is not managed by Terraform for this container.
- Credentials: `secrets.auto.tfvars` (gitignored) — see `secrets.auto.tfvars.example`
- Token: `root@pam!terraform` (must be root@pam; other users blocked from privileged containers)

## Ansible

- Inventory: `ansible/inventory/hosts.yml`
- Vault: `ansible/group_vars/ollama_hosts/vault.yml` — **not currently encrypted** (placeholder only); run without `--ask-vault-pass`
- Run with: `ansible-playbook ansible/site.yml -i ansible/inventory/hosts.yml`
- Roles: `nvidia_userspace` → `ollama` → `open_webui` → `anything_llm`
- Docker services use `--security-opt apparmor=unconfined` — required inside privileged LXC

## Known Gotchas

| Issue | Fix |
|---|---|
| Proxmox API token (even `root@pam`) cannot create privileged containers | Use `pct create` over SSH via `just provision` |
| Docker inside LXC blocked by AppArmor | `--security-opt apparmor=unconfined` in each `docker run` + `lxc.apparmor.profile: unconfined` in LXC conf |
| Ollama install script requires `zstd` | Installed as prerequisite in the `ollama` role |
| AnythingLLM SQLite can't write to storage | Storage dir must be `mode: 0777` |
| `gpu-passthrough` heredoc fails in just | Config is in `scripts/lxc-202-gpu.conf`, transferred via `scp` |

## Default Model

`qwen2.5:3b` — small, fits in limited VRAM scenarios. Custom model `analysis-assistant` built on top via Modelfile (see `ansible/roles/ollama/templates/Modelfile.j2`).

## Reference Docs

- [Docker Ollama Reference](docs/docker-ollama-reference.md) — original Docker setup knowledge
- [Proxmox LXC Terraform Guide](docs/proxmox-lxc-terraform-guide.md)
- [LXC GPU Passthrough Plan](docs/plans/Completed/lxc-gpu-passthrough.md) — completed, includes lessons learned
- [Migration Plan](docs/plans/Completed/migrate-to-terraform-ansible.md)

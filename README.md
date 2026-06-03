# proxmox-ollama

Terraform + Ansible infrastructure for running Ollama on a Proxmox LXC container with NVIDIA GPU passthrough.

**Target:** LXC 202 — `192.168.2.202` — NVIDIA GeForce RTX 3060 (12 GB VRAM)

---

## Stack

| Layer     | Tool      | Purpose                                      |
|-----------|-----------|----------------------------------------------|
| Provision | Terraform | Create/manage LXC container 202 on Proxmox   |
| Configure | Ansible   | Install NVIDIA userspace libs, Ollama, UIs   |
| Task runner | just    | Wrap common terraform/ansible/SSH ops         |

### Services on LXC 202

| Service       | Port  | URL                              |
|---------------|-------|----------------------------------|
| Ollama API    | 11434 | `http://192.168.2.202:11434`     |
| Open WebUI    | 3000  | `http://192.168.2.202:3000`      |
| AnythingLLM   | 3001  | `http://192.168.2.202:3001`      |

---

## Quick Start

```bash
# 1. Set Proxmox credentials
export PROXMOX_VE_ENDPOINT="https://<proxmox-host>:8006/"
export PROXMOX_VE_API_TOKEN="root@pam!terraform=<secret>"

# 2. Provision LXC container 202
just provision

# 3. Patch GPU device mounts into /etc/pve/lxc/202.conf (run once)
just gpu-passthrough

# 4. Configure container (install NVIDIA libs, Ollama, UIs)
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
│   │   ├── vars.yml          # non-secret config
│   │   └── vault.yml         # encrypted secrets (ansible-vault)
│   ├── roles/
│   │   ├── nvidia_userspace/ # userspace libs matching Proxmox host driver (595.71.05)
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
│   ├── docker-ollama-reference.md   # archived Docker knowledge
│   ├── proxmox-lxc-terraform-guide.md
│   ├── django-drf-react-rag-ollama.md
│   └── plans/
│       └── migrate-to-terraform-ansible.md
├── scripts/
│   └── status.py                    # queries VM 202 Ollama API
├── justfile
└── CLAUDE.md
```

---

## Prerequisites

- Terraform >= 1.5
- Ansible >= 2.14
- `just` task runner
- SSH key at `~/.ssh/id_ed25519`
- Proxmox API token (see `docs/proxmox-lxc-terraform-guide.md`)

---

## Common Commands

```bash
just provision          # terraform init + apply (create LXC container)
just gpu-passthrough    # patch GPU mounts into /etc/pve/lxc/202.conf (once after provision)
just deploy             # ansible-playbook site.yml
just deploy-check       # dry run (--check)
just status             # query Ollama API on container 202
just models             # list models on container 202
just pull mistral       # pull a model
just logs               # tail Ollama systemd logs on container 202
just gpu                # nvidia-smi on container 202
just vault-edit         # edit encrypted secrets
just ssh                # SSH into container 202
just ct-stop            # stop LXC container 202
just ct-start           # start LXC container 202
```

---

## Secrets

Secrets (Open WebUI admin password, etc.) are stored in `ansible/group_vars/ollama_hosts/vault.yml` encrypted with Ansible Vault.

```bash
# Create
ansible-vault create ansible/group_vars/ollama_hosts/vault.yml

# Edit
ansible-vault edit ansible/group_vars/ollama_hosts/vault.yml

# Run playbook with vault
ansible-playbook ansible/site.yml --ask-vault-pass
# or with a password file:
ansible-playbook ansible/site.yml --vault-password-file ~/.vault_pass
```

---

## Reference

- [Docker Ollama Reference](docs/docker-ollama-reference.md) — archived Docker knowledge
- [Proxmox LXC Terraform Guide](docs/proxmox-lxc-terraform-guide.md)
- [Migration Plan](docs/plans/migrate-to-terraform-ansible.md)

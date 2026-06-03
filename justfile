OLLAMA_HOST := "192.168.2.202"
OLLAMA_URL  := "http://" + OLLAMA_HOST + ":11434"
SSH_USER    := "ubuntu"
TF_DIR      := "terraform/vm202-ollama"
ANSIBLE_DIR := "ansible"
MODEL       := "qwen2.5:3b"

# Show available commands
default:
    @just --list

# ── Terraform ───────────────────────────────────────────────────────────────

# Initialise Terraform (run once)
[group('Terraform')]
tf-init:
    cd {{TF_DIR}} && terraform init

# Preview infrastructure changes
[group('Terraform')]
tf-plan:
    cd {{TF_DIR}} && terraform plan

# Provision VM 202 on Proxmox
[group('Terraform')]
provision:
    cd {{TF_DIR}} && terraform init -upgrade && terraform apply

# Destroy VM 202 (DANGEROUS — prompts for confirmation)
[group('Terraform')]
tf-destroy:
    cd {{TF_DIR}} && terraform destroy

# Show Terraform outputs (IP, SSH command)
[group('Terraform')]
tf-output:
    cd {{TF_DIR}} && terraform output

# ── Ansible ─────────────────────────────────────────────────────────────────

# Test connectivity to VM 202
[group('Ansible')]
ping:
    ansible vm202 -i {{ANSIBLE_DIR}}/inventory/hosts.yml -m ping

# Run the full playbook (installs drivers, Ollama, Open WebUI, AnythingLLM)
[group('Ansible')]
deploy:
    ansible-playbook {{ANSIBLE_DIR}}/site.yml \
        -i {{ANSIBLE_DIR}}/inventory/hosts.yml \
        --ask-vault-pass

# Dry-run the playbook (no changes applied)
[group('Ansible')]
deploy-check:
    ansible-playbook {{ANSIBLE_DIR}}/site.yml \
        -i {{ANSIBLE_DIR}}/inventory/hosts.yml \
        --ask-vault-pass \
        --check --diff

# Run only the ollama role (skip driver install)
[group('Ansible')]
deploy-ollama:
    ansible-playbook {{ANSIBLE_DIR}}/site.yml \
        -i {{ANSIBLE_DIR}}/inventory/hosts.yml \
        --ask-vault-pass \
        --tags ollama

# Run only the open_webui role
[group('Ansible')]
deploy-webui:
    ansible-playbook {{ANSIBLE_DIR}}/site.yml \
        -i {{ANSIBLE_DIR}}/inventory/hosts.yml \
        --ask-vault-pass \
        --tags open_webui

# Edit encrypted vault secrets
[group('Ansible')]
vault-edit:
    ansible-vault edit {{ANSIBLE_DIR}}/group_vars/ollama_hosts/vault.yml

# Add RTX 3060 PCIe passthrough to VM 202 (run once after provision, requires Proxmox sudo)
# Proxmox API tokens cannot set unmapped hostpci devices — must go via SSH
[group('Terraform')]
gpu-passthrough:
    ssh proxmox "echo 3719 | sudo -Sp '' qm set 202 --hostpci0 '0000:01:00,pcie=1,rombar=1' --vga none"
    @echo "GPU passthrough added. VM 202 must be stopped first, then started: just vm-start"

# Stop VM 202 on Proxmox (required before changing hardware)
[group('Terraform')]
vm-stop:
    ssh proxmox "echo 3719 | sudo -Sp '' qm stop 202"

# Start VM 202 on Proxmox
[group('Terraform')]
vm-start:
    ssh proxmox "echo 3719 | sudo -Sp '' qm start 202"

# ── VM 202 Operations ───────────────────────────────────────────────────────

# SSH into VM 202
[group('VM 202')]
ssh:
    ssh {{SSH_USER}}@{{OLLAMA_HOST}}

# Query Ollama API status, GPU, and loaded models
[group('VM 202')]
status:
    @python3 scripts/status.py

# List all downloaded models on VM 202
[group('VM 202')]
models:
    @curl -s {{OLLAMA_URL}}/api/tags | python3 -c \
        "import json,sys; [print(m['name'], f\"{m.get('size',0)/1e9:.2f}GB\") for m in json.load(sys.stdin).get('models',[])]"

# Pull a model — usage: just pull mistral
[group('VM 202')]
pull model=MODEL:
    ssh {{SSH_USER}}@{{OLLAMA_HOST}} "ollama pull {{model}}"

# Remove a model — usage: just remove mistral
[group('VM 202')]
remove model=MODEL:
    ssh {{SSH_USER}}@{{OLLAMA_HOST}} "ollama rm {{model}}"

# Show GPU stats on VM 202
[group('VM 202')]
gpu:
    ssh {{SSH_USER}}@{{OLLAMA_HOST}} nvidia-smi

# Tail Ollama systemd logs on VM 202
[group('VM 202')]
logs:
    ssh {{SSH_USER}}@{{OLLAMA_HOST}} "journalctl -fu ollama"

# Restart Ollama service on VM 202
[group('VM 202')]
restart-ollama:
    ssh {{SSH_USER}}@{{OLLAMA_HOST}} "sudo systemctl restart ollama"

# Check all service statuses on VM 202
[group('VM 202')]
service-status:
    ssh {{SSH_USER}}@{{OLLAMA_HOST}} "systemctl status ollama open-webui anything-llm"

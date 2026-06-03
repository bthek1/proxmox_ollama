# Docker Ollama Reference

Archived knowledge from the original Docker Compose deployment of Ollama on the host machine (`192.168.2.28`). This setup has been superseded by the Terraform + Ansible deployment on VM 202 (`192.168.2.202`).

---

## Stack Summary

| Service        | Image                                    | Port  | Purpose                     |
|----------------|------------------------------------------|-------|-----------------------------|
| `ollama`       | `ollama/ollama:latest`                   | 11434 | LLM inference server        |
| `ollama-init`  | `ollama/ollama:latest`                   | —     | One-shot: pull model + build custom model |
| `open-webui`   | `ghcr.io/open-webui/open-webui:latest`   | 3000  | Browser chat UI             |
| `anything-llm` | `mintplexlabs/anythingllm:latest`        | 3001  | RAG / document chat UI      |

---

## Full `docker-compose.yml` (Annotated)

```yaml
services:
  ollama:
    image: ollama/ollama:latest
    container_name: ollama
    restart: unless-stopped
    ports:
      - "127.0.0.1:11434:11434"       # loopback only — local CLI access
      - "192.168.2.28:11434:11434"    # LAN — accessible on local network
    volumes:
      # Bind mount: host path → container path (models persist outside container)
      - /home/bthek1/ollama_doc/models:/root/.ollama/models
    environment:
      OLLAMA_NUM_PARALLEL: "1"          # max concurrent inference requests
      OLLAMA_MAX_LOADED_MODELS: "2"     # models held in GPU VRAM simultaneously
      OLLAMA_FLASH_ATTENTION: "1"       # enable flash attention (speed + VRAM savings)
      OLLAMA_KEEP_ALIVE: "10m"          # how long to keep a model loaded after last request
      # CORS — which origins may call the Ollama API directly from a browser
      OLLAMA_ORIGINS: "http://localhost:3000,http://127.0.0.1:3000,http://192.168.2.28:3000,http://localhost:8000,http://192.168.2.28:8000"
    devices:
      # NVIDIA CDI passthrough — works with cgroup v2, requires nvidia-container-toolkit
      - "nvidia.com/gpu=all"
    networks:
      - ollama-network
    healthcheck:
      test: ["CMD", "ollama", "list"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 20s   # give Ollama time to load before first check

  ollama-init:
    # Sidecar that runs once after ollama is healthy: pulls the default model
    # and creates the custom analysis-assistant model from a Modelfile.
    image: ollama/ollama:latest
    container_name: ollama-init
    depends_on:
      ollama:
        condition: service_healthy
    environment:
      OLLAMA_HOST: "http://ollama:11434"  # uses Docker DNS to reach ollama container
    volumes:
      - ./Modelfile:/tmp/Modelfile:ro     # inject Modelfile read-only
    networks:
      - ollama-network
    entrypoint: >
      sh -c "
        ollama pull qwen2.5:3b &&
        ollama create analysis-assistant -f /tmp/Modelfile
      "
    restart: "no"   # run once only — never restart

  open-webui:
    image: ghcr.io/open-webui/open-webui:latest
    container_name: open-webui
    restart: unless-stopped
    ports:
      - "192.168.2.28:3000:8080"     # Open WebUI listens on 8080 internally, exposed as 3000
    env_file: .env                   # loads SUPERUSER_EMAIL/USERNAME/PASSWORD
    environment:
      OLLAMA_BASE_URL: "http://192.168.2.28:11434"
      OLLAMA_SHOW_ADMIN_DETAILS: "True"
      SCOPED_MODEL_PERMISSIONS: "True"          # limit model visibility per user
      WEBUI_SECRET_KEY: "<secret>"              # session token signing key
      WEBUI_ADMIN_EMAIL: "${SUPERUSER_EMAIL}"   # set admin account on first boot
      WEBUI_ADMIN_USERNAME: "${SUPERUSER_USERNAME}"
      WEBUI_ADMIN_PASSWORD: "${SUPERUSER_PASSWORD}"
    volumes:
      - open-webui-data:/app/backend/data   # SQLite DB, uploads, settings
    networks:
      - ollama-network
    depends_on:
      ollama:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s

  anything-llm:
    image: mintplexlabs/anythingllm:latest
    container_name: anything-llm
    restart: unless-stopped
    ports:
      - "192.168.2.28:3001:3001"
    environment:
      NODE_ENV: "production"
      STORAGE_DIR: "/app/server/storage"
      LLM_PROVIDER: "ollama"
      OLLAMA_BASE_URL: "http://192.168.2.28:11434"
    volumes:
      - anything-llm-data:/app/server/storage
    networks:
      - ollama-network
    depends_on:
      ollama:
        condition: service_healthy

volumes:
  open-webui-data:
    driver: local
  anything-llm-data:
    driver: local

networks:
  ollama-network:
    driver: bridge
```

---

## Environment Variables

### Ollama tunables

| Variable                   | Value used | Effect                                              |
|----------------------------|------------|-----------------------------------------------------|
| `OLLAMA_NUM_PARALLEL`      | `1`        | Serialize requests; avoids VRAM OOM on small GPUs  |
| `OLLAMA_MAX_LOADED_MODELS` | `2`        | Keep up to 2 models hot in VRAM                    |
| `OLLAMA_FLASH_ATTENTION`   | `1`        | Flash attention — faster inference, less VRAM      |
| `OLLAMA_KEEP_ALIVE`        | `10m`      | Unload model 10 min after last request             |
| `OLLAMA_ORIGINS`           | see above  | CORS allowlist for browser-to-API calls            |
| `OLLAMA_HOST`              | `0.0.0.0:11434` | (systemd) bind on all interfaces             |

### Open WebUI

| Variable                   | Purpose                                          |
|----------------------------|--------------------------------------------------|
| `OLLAMA_BASE_URL`          | Ollama API endpoint Open WebUI connects to       |
| `OLLAMA_SHOW_ADMIN_DETAILS`| Show model/system details in admin UI            |
| `SCOPED_MODEL_PERMISSIONS` | Admins can restrict which users see which models |
| `WEBUI_SECRET_KEY`         | Signs session cookies — keep secret, rotate it  |
| `WEBUI_ADMIN_EMAIL`        | Pre-seeds admin account email on first boot      |
| `WEBUI_ADMIN_USERNAME`     | Pre-seeds admin username                         |
| `WEBUI_ADMIN_PASSWORD`     | Pre-seeds admin password                         |

### `.env` file (gitignored)

```bash
SUPERUSER_EMAIL=admin@example.com
SUPERUSER_USERNAME=admin
SUPERUSER_PASSWORD=changeme
```

---

## NVIDIA GPU Passthrough (Docker / CDI)

The Docker deployment used **NVIDIA CDI** (Container Device Interface), which works with cgroup v2:

```yaml
devices:
  - "nvidia.com/gpu=all"
```

### Requirements
- `nvidia-container-toolkit` installed on the host
- Docker configured to use NVIDIA runtime: `nvidia-ctk runtime configure --runtime=docker`
- CDI spec generated: `nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml`
- cgroup v2 enabled on host kernel

### Setup script (`phase6-setup.sh`)
```bash
# Add NVIDIA Container Toolkit repo
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
  | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
  | sed 's#deb https://#deb [signed-by=...] https://#g' \
  | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
sudo apt-get update && sudo apt-get install -y nvidia-container-toolkit
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
```

---

## Modelfile (`analysis-assistant`)

```dockerfile
FROM qwen2.5:3b

SYSTEM "You are a helpful assistant specialised in analysis and summarisation. When asked to analyse, identify key themes, patterns, and insights. When asked to summarise, be concise yet comprehensive. Always structure your responses clearly."

PARAMETER temperature 0.4
PARAMETER num_ctx 4096
```

Built with:
```bash
# Docker approach (old)
docker cp Modelfile ollama:/tmp/Modelfile
docker exec ollama ollama create analysis-assistant -f /tmp/Modelfile

# Native Ollama (new)
ollama create analysis-assistant -f /path/to/Modelfile
```

---

## Storage Strategy

### Models (bind mount)
```
Host:      /home/bthek1/ollama_doc/models/
Container: /root/.ollama/models
```
Models live on the host filesystem — they survive `docker compose down` and container rebuilds.

### Open WebUI data (named volume)
```
Volume: open-webui-data → /app/backend/data
```
Contains SQLite database, uploaded documents, user settings.

### AnythingLLM data (named volume)
```
Volume: anything-llm-data → /app/server/storage
```

### Backup Open WebUI data
```bash
docker run --rm \
  -v open-webui-data:/data \
  -v $(pwd):/backup \
  alpine tar czf /backup/open-webui-backup.tar.gz /data
```

---

## Python Tooling

### Dependencies (`pyproject.toml`)
```toml
dependencies = [
    "httpx>=0.28.1",
    "llm>=0.29",
    "llm-ollama>=0.15.1",
    "ollama>=0.6.1",
    "openai>=2.29.0",
    "rich>=14.3.3",
]
```

Managed with `uv`:
```bash
uv sync                         # install into .venv
uv run python main.py           # diagnostics
uv run python scripts/status.py # quick status
```

### `main.py` — Diagnostics
- Checks if Ollama is running (`/api/version`)
- Detects GPU via `nvidia-smi`
- Lists local models (`ollama.list()`)
- Shows loaded models in VRAM (`ollama.ps()`)
- Generates 10 random prompts via LLM
- Runs all 10 prompts as a streaming batch query

### `scripts/status.py` — Quick status
- Queries `/api/version`, `/api/ps`, `/api/tags`
- Gets GPU stats via `docker exec ollama nvidia-smi`
- Prints rich tables of loaded models and GPU state
- Sends a "hi" greeting to first loaded model

---

## Python API Examples

```python
import ollama

# Streaming chat
for chunk in ollama.chat(
    model="qwen2.5:3b",
    messages=[{"role": "user", "content": "Why is the sky blue?"}],
    stream=True,
):
    print(chunk.message.content, end="", flush=True)

# List local models
models = ollama.list().models

# Check loaded models in VRAM
running = ollama.ps().models

# Non-streaming generate
response = ollama.generate(model="qwen2.5:3b", prompt="Hello")
print(response.response)
```

---

## REST API Examples

```bash
# Chat (non-streaming)
curl http://localhost:11434/api/chat \
  -d '{"model":"qwen2.5:3b","messages":[{"role":"user","content":"Hello!"}],"stream":false}'

# Generate
curl http://localhost:11434/api/generate \
  -d '{"model":"qwen2.5:3b","prompt":"Why is the sky blue?","stream":false}'

# List models
curl http://localhost:11434/api/tags

# Server version
curl http://localhost:11434/api/version

# Loaded models
curl http://localhost:11434/api/ps
```

---

## Healthcheck Patterns

```yaml
# Ollama — checks model list is accessible (proves inference engine is ready)
healthcheck:
  test: ["CMD", "ollama", "list"]
  interval: 30s
  timeout: 10s
  retries: 5
  start_period: 20s   # important: Ollama takes ~15s to initialise

# Open WebUI — HTTP health endpoint
healthcheck:
  test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
  interval: 30s
  timeout: 10s
  retries: 3
  start_period: 30s   # Open WebUI takes longer — DB migrations on first boot
```

---

## Recommended Models

| Use Case        | Model          | Size   |
|-----------------|----------------|--------|
| General chat    | `llama3.2`     | ~2 GB  |
| General chat    | `mistral`      | ~4 GB  |
| Code generation | `codellama`    | ~4 GB  |
| Small / fast    | `phi3`         | ~2 GB  |
| Analysis        | `qwen2.5:3b`   | ~2 GB  |

Pull a model:
```bash
# Docker (old)
docker exec ollama ollama pull mistral

# Native (new)
ollama pull mistral
```

---

## Troubleshooting (Docker)

### Open WebUI cannot connect to Ollama
```bash
# Check containers
docker compose ps
# Check network connectivity from webui container
docker exec open-webui curl http://ollama:11434/api/tags
# View logs
docker compose logs ollama
docker compose logs open-webui
```

### CORS errors
- Verify `OLLAMA_ORIGINS` includes the WebUI origin
- Restart after updating: `docker compose restart ollama`

### GPU not detected inside container
```bash
# Verify CDI spec exists
ls /etc/cdi/
# Re-generate CDI spec
sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml
# Check docker runtime config
cat /etc/docker/daemon.json
```

### Model OOM (out of VRAM)
- Reduce `OLLAMA_MAX_LOADED_MODELS` to `1`
- Use a smaller model (`phi3` or `qwen2.5:3b`)
- Unload idle models: `docker exec ollama ollama stop <model>`

# Ollama API Reference — LXC 202

Ollama is running on LXC container 202 in Proxmox and is accessible from any machine on the local network.

## Connection Details

| Property | Value |
|----------|-------|
| Base URL | `http://192.168.2.202:11434` |
| Version | 0.30.2 |
| Auth | None — open, LAN only |

---

## Available Models

| Model | Size | Use for |
|-------|------|---------|
| `qwen2.5:3b` | 1.93 GB | General generation, chat |
| `qwen3:8b` | 5.23 GB | Larger generation — tools + thinking |
| `nomic-embed-text` | 0.27 GB | Embeddings / RAG — 768-dimensional vectors |

Pull additional models via SSH:
```bash
ssh root@192.168.2.202 "ollama pull <model>"
```

---

## REST API

All endpoints are standard Ollama REST. Full spec: https://github.com/ollama/ollama/blob/main/docs/api.md

### Health check

```bash
curl http://192.168.2.202:11434/api/version
# → {"version":"0.30.2"}
```

### List available models

```bash
curl http://192.168.2.202:11434/api/tags
```

### Generate (non-streaming)

```bash
curl http://192.168.2.202:11434/api/generate \
  -d '{
    "model": "qwen2.5:3b",
    "prompt": "Explain LXC containers in one sentence.",
    "stream": false
  }'
```

### Generate (streaming)

```bash
curl http://192.168.2.202:11434/api/generate \
  -d '{
    "model": "qwen2.5:3b",
    "prompt": "Explain LXC containers in one sentence."
  }'
```

### Chat (multi-turn)

```bash
curl http://192.168.2.202:11434/api/chat \
  -d '{
    "model": "qwen2.5:3b",
    "messages": [
      {"role": "system", "content": "You are a concise assistant."},
      {"role": "user",   "content": "What is Ollama?"}
    ]
  }'
```

### Embeddings

**Use `nomic-embed-text`** — chat models (`qwen2.5:3b`) do not support embeddings in Ollama 0.30.2.

```bash
curl http://192.168.2.202:11434/api/embed \
  -d '{
    "model": "nomic-embed-text",
    "input": "Your text here"
  }'
# → {"model":"nomic-embed-text","embeddings":[[0.028, -0.191, ...]]}
# Vector dimension: 768
```

### OpenAI-compatible endpoint

Ollama exposes an OpenAI-compatible API at `/v1`:

```bash
curl http://192.168.2.202:11434/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen2.5:3b",
    "messages": [{"role": "user", "content": "Hello"}]
  }'
```

---

## Python

### Using the official `ollama` client

```python
import ollama

client = ollama.Client(host="http://192.168.2.202:11434")

# Generate
response = client.generate(model="qwen2.5:3b", prompt="Hello")
print(response.response)

# Chat
response = client.chat(model="qwen2.5:3b", messages=[
    {"role": "user", "content": "Hello"}
])
print(response.message.content)

# Embeddings — use nomic-embed-text, not a chat model
response = client.embed(model="nomic-embed-text", input="Some text")
vector = response.embeddings[0]   # list[float], len=768
```

Install: `uv add ollama` or `pip install ollama`

### Using the OpenAI client (compatible mode)

```python
from openai import OpenAI

client = OpenAI(
    base_url="http://192.168.2.202:11434/v1",
    api_key="ollama",   # required by client but not validated
)

response = client.chat.completions.create(
    model="qwen2.5:3b",
    messages=[{"role": "user", "content": "Hello"}],
)
print(response.choices[0].message.content)
```

Install: `uv add openai` or `pip install openai`

### Streaming

```python
import ollama

client = ollama.Client(host="http://192.168.2.202:11434")

for chunk in client.generate(model="qwen2.5:3b", prompt="Count to 5", stream=True):
    print(chunk.response, end="", flush=True)
```

---

## JavaScript / TypeScript

```typescript
import ollama from "ollama";

const client = new ollama.Ollama({ host: "http://192.168.2.202:11434" });

// Generate
const response = await client.generate({
  model: "qwen2.5:3b",
  prompt: "Hello",
});
console.log(response.response);

// Embeddings
const embed = await client.embed({
  model: "nomic-embed-text",
  input: "Some text",
});
console.log(embed.embeddings[0].length); // 768
```

Install: `npm install ollama`

---

## LangChain

```python
from langchain_ollama import ChatOllama, OllamaEmbeddings

# Chat model
llm = ChatOllama(
    model="qwen2.5:3b",
    base_url="http://192.168.2.202:11434",
)
response = llm.invoke("Hello")

# Embeddings — must use nomic-embed-text
embeddings = OllamaEmbeddings(
    model="nomic-embed-text",
    base_url="http://192.168.2.202:11434",
)
vector = embeddings.embed_query("Some text")   # len=768
```

Install: `uv add langchain-ollama`

---

## Environment Variable Pattern

Most Ollama-aware tools accept `OLLAMA_HOST` to point at a remote server:

```bash
export OLLAMA_HOST=http://192.168.2.202:11434
ollama list       # lists models on LXC 202 (if ollama CLI is installed locally)
```

---

## Known Limitations (Ollama 0.30.2)

| Limitation | Detail |
|---|---|
| Chat models cannot generate embeddings | `qwen2.5:3b` returns HTTP 501 from `/api/embed`. Always use `nomic-embed-text` for embeddings. |
| No authentication | The API is open on the LAN. Do not expose port 11434 externally without adding a reverse proxy with auth. |
| Single GPU | RTX 3060 has 12 GB VRAM. Large models (>8B params) may not fit alongside other loaded models. |
| `OLLAMA_MAX_LOADED_MODELS=2` | At most 2 models in VRAM simultaneously. A third request will evict the LRU model (adds ~3–5 s cold-start). |

---

## GPU

NVIDIA GeForce RTX 3060, 12 GB VRAM. Driver `595.71.05` on the Proxmox host — shared into LXC 202 via device passthrough.

Check live GPU usage:
```bash
ssh root@192.168.2.202 nvidia-smi
```

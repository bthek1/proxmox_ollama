# Plan: uv Python Environment + Ollama API Test Client

> **Status: COMPLETED 2026-06-03** — all 6 test sections pass.

---

## Goal

Add a proper `uv`-managed Python project with a test script that exercises the Ollama API on LXC 202 (`192.168.2.202:11434`). Local developer tool — not deployed to the container.

---

## What Was Built

| File | Purpose |
|------|---------|
| `pyproject.toml` | uv project manifest — `proxmox-ollama-tools` |
| `uv.lock` | Pinned dependency lockfile (22 packages) |
| `scripts/test_ollama.py` | 6-section Ollama API test client |
| `justfile` | Added `test-api` recipe; removed `status` recipe |

`scripts/status.py` was **removed** (the plan initially said to keep it — decision reversed during implementation; `test_ollama.py` covers everything it did and more).

### Dependencies

```
ollama>=0.4    # official Python client
httpx>=0.28    # raw HTTP for health checks
rich>=13       # formatted terminal output
pytest>=8      # dev dependency
```

### Test Sections

| Section | Endpoint | Result |
|---------|----------|--------|
| Health | `GET /`, `GET /api/version` | PASS |
| List models | `GET /api/tags` | PASS |
| Running models | `GET /api/ps` | PASS |
| Generate (non-stream) | `POST /api/generate` | PASS |
| Generate (stream) | `POST /api/generate` streaming | PASS |
| Chat (multi-turn) | `POST /api/chat` | PASS |
| Embeddings | `POST /api/embed` | PASS (with `nomic-embed-text`) |

### Running

```bash
just test-api                              # uses qwen2.5:3b + nomic-embed-text
MODEL=analysis-assistant just test-api    # override generation model
EMBED_MODEL=mxbai-embed-large just test-api  # override embedding model
```

---

## Lessons Learned

### Ollama 0.30.2 does not support embeddings for chat models

The original plan assumed embeddings would work with `qwen2.5:3b`. They don't in 0.30.2:

- `POST /api/embed` → HTTP 501 with `"Start it with --embeddings"`
- `POST /api/embeddings` → same error
- `OLLAMA_EMBEDDINGS=1` env var → ignored (not a recognised variable in this version)
- `ollama serve --embeddings` → `Error: unknown flag: --embeddings`

The 501 originates from the **llama_server** subprocess (visible in `journalctl -u ollama`): `POST /v1/embeddings 127.0.0.1 501`. When Ollama 0.30.2 spawns `llama_server` for a chat model it doesn't pass the embedding flag to llama.cpp.

**Fix:** Pull `nomic-embed-text` (274 MB, `nomic-bert` family). Ollama starts `llama_server` correctly for this model and `/api/embed` returns 768-dimensional vectors.

The test script uses a separate `EMBED_MODEL` env var (default: `nomic-embed-text`) so the generation model and embedding model can be configured independently.

### `uv sync` rebuilt the venv

The existing `.venv` was created ad-hoc without a `pyproject.toml`. `uv sync` on the new `pyproject.toml` cleanly replaced it, removing 30 packages that were no longer needed (llm, openai, sqlite-utils, etc.) and installing the 12 that are.

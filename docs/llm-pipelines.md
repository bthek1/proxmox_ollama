# LLM Pipeline Patterns

Overview of the main ways to build on top of a local LLM like Ollama.

---

## 1. Direct Inference

The simplest pattern. A single prompt goes in, a single response comes out. Stateless — no memory of previous calls.

```
┌─────────┐        ┌─────────┐        ┌──────────┐
│  User   │──────▶ │  Prompt │──────▶ │   LLM    │──────▶  Response
└─────────┘        └─────────┘        └──────────┘
```

**Good for:**
- One-shot text generation
- Summarisation
- Classification / labelling
- Code generation
- Translation

**Ollama example:**
```bash
curl http://192.168.2.202:11434/api/generate \
  -d '{"model": "qwen2.5:3b", "prompt": "Summarise this text: ...", "stream": false}'
```

---

## 2. Chat / Multi-turn

The full conversation history is sent with every request. "Memory" is just the accumulating message list. The LLM has no built-in state — the client owns the history.

```
┌─────────────────────────────────────────────────────┐
│  Message history                                    │
│  ┌──────────────────────────────────────────────┐  │
│  │ system:    You are a helpful assistant.      │  │
│  │ user:      What is Proxmox?                  │  │
│  │ assistant: Proxmox is a hypervisor...        │  │
│  │ user:      How does LXC differ from a VM?    │  │◀── new message
│  └──────────────────────────────────────────────┘  │
└────────────────────────┬────────────────────────────┘
                         │
                         ▼
                    ┌─────────┐
                    │   LLM   │──────▶  Response ──▶ append to history
                    └─────────┘
```

**Good for:**
- Conversational assistants
- Interactive debugging sessions
- Anything requiring follow-up questions

**Limit:** context window. Once history exceeds the model's context length, older messages must be dropped or summarised.

---

## 3. RAG — Retrieval-Augmented Generation

Documents are pre-processed into a vector database. At query time the most relevant chunks are retrieved and injected into the prompt, giving the LLM access to knowledge it was never trained on.

```
  INDEXING (done once, or on document update)
  ════════════════════════════════════════════

  Documents
  ┌──────────┐   chunk    ┌────────────────────┐   embed   ┌─────────────┐
  │ PDF, MD, │──────────▶ │  chunk₁  chunk₂    │─────────▶ │  Vector DB  │
  │ code...  │            │  chunk₃  chunk₄... │           │  (indexed)  │
  └──────────┘            └────────────────────┘           └─────────────┘
                                                             ▲
                                                   nomic-embed-text


  QUERYING (every user request)
  ══════════════════════════════

  User query
      │
      ├──▶ embed query ──▶ nomic-embed-text ──▶ query vector
      │                                               │
      │                                               ▼
      │                                        ┌─────────────┐
      │                                        │  Vector DB  │──▶ top-k chunks
      │                                        └─────────────┘
      │                                               │
      ▼                                               ▼
  ┌───────────────────────────────────────────────────────────┐
  │  Prompt                                                   │
  │  ┌───────────────────────────────────────────────────┐   │
  │  │ Context:                                          │   │
  │  │   [chunk₁] ...relevant text...                   │   │
  │  │   [chunk₂] ...relevant text...                   │   │
  │  │                                                   │   │
  │  │ Question: <user query>                            │   │
  │  └───────────────────────────────────────────────────┘   │
  └──────────────────────────┬────────────────────────────────┘
                             │
                             ▼
                        ┌─────────┐
                        │   LLM   │──────▶  Response grounded in your documents
                        └─────────┘
```

**Good for:**
- Q&A over your own documents, code, or knowledge base
- Avoiding hallucination on domain-specific facts
- Keeping the model's knowledge current without retraining

**On LXC 202:** AnythingLLM (port 3001) implements this pattern.
- Embedding model: `nomic-embed-text` → 768-dimensional vectors
- Generation model: `qwen2.5:3b`

---

## 4. Agents / Tool Use

The LLM is given a set of tools (functions it can call). It decides which tool to invoke, receives the result, reasons over it, and either calls another tool or returns a final answer. The loop continues until the task is complete.

```
  User: "What's the GPU temperature on LXC 202 right now?"
    │
    ▼
┌─────────┐
│   LLM   │──▶ "I need to run nvidia-smi. Calling: run_ssh_command(cmd='nvidia-smi')"
└─────────┘
    │
    │  tool call
    ▼
┌──────────────┐
│  Tool runner │──▶ ssh root@192.168.2.202 nvidia-smi
└──────────────┘
    │
    │  result: "GPU 0: 42°C, utilisation 0%"
    ▼
┌─────────┐
│   LLM   │──▶ "The GPU is currently at 42°C and idle."
└─────────┘
    │
    ▼
  Response to user
```

**Multi-step example:**

```
User query
    │
    ▼
  LLM ──▶ tool call ──▶ result
    │                      │
    └──────────────────────┘
    │
    ▼
  LLM ──▶ tool call ──▶ result        (loop until done)
    │                      │
    └──────────────────────┘
    │
    ▼
  Final answer
```

**Good for:**
- Autonomous task execution
- Anything requiring real-world data (web search, APIs, databases, file system)
- Multi-step reasoning with external state

**Common tools:** web search, code execution, file read/write, database query, API calls.

---

## 5. Chain-of-Thought / Structured Reasoning

The LLM is prompted (or trained) to reason through a problem step-by-step before producing a final answer. The scratchpad reasoning improves accuracy on complex tasks.

```
  Standard prompting
  ──────────────────
  Question ──▶ LLM ──▶ Answer

  Chain-of-thought
  ────────────────
  Question ──▶ LLM ──▶ ┌─────────────────────────────────────────────┐
                        │  <think>                                    │
                        │    Step 1: Identify what is being asked...  │
                        │    Step 2: Consider constraints...          │
                        │    Step 3: Calculate...                     │
                        │  </think>                                   │
                        │                                             │
                        │  Final answer: ...                          │
                        └─────────────────────────────────────────────┘
```

**Trigger methods:**
- Prompt: append `"Think step by step."` to your prompt
- Dedicated reasoning models: DeepSeek-R1, QwQ, o1-style models

**Good for:**
- Maths and logic problems
- Multi-step code reasoning
- Anything where intermediate steps matter

---

## 6. Prompt Chaining

The output of one LLM call feeds directly into the next. Each step does one narrowly-scoped thing, which is easier to get right than one massive prompt trying to do everything.

```
  User input
      │
      ▼
  ┌─────────┐    extract key facts
  │  LLM₁  │──────────────────────▶  structured data
  └─────────┘
                                           │
                                           ▼
                                      ┌─────────┐    classify intent
                                      │  LLM₂  │──────────────────▶  category
                                      └─────────┘
                                                              │
                                                              ▼
                                                         ┌─────────┐
                                                         │  LLM₃  │──▶ final response
                                                         └─────────┘
                                                    generate using facts + category
```

**Generate → Critique → Revise pattern:**

```
  Prompt
    │
    ▼
  LLM₁ ──▶ draft
              │
              ▼
            LLM₂ ──▶ critique  ("too vague, missing X")
                        │
                        ▼
                      LLM₃ ──▶ revised final output
```

**Good for:**
- Complex tasks too long or too ambiguous for a single prompt
- Quality control loops
- Separating concerns (extract, classify, generate are independent steps)

---

## 7. Map-Reduce

A large input (long document, many files, large dataset) is split into chunks that are processed in parallel, then the results are merged into a single output.

```
  Large input (e.g. 200-page PDF)
        │
        │  split
        ▼
  ┌──────────────────────────────────┐
  │  chunk₁  chunk₂  chunk₃  chunk₄ │
  └──────┬───────┬───────┬───────┬──┘
         │       │       │       │
    (parallel LLM calls)
         │       │       │       │
         ▼       ▼       ▼       ▼
       sum₁    sum₂    sum₃    sum₄        ← map phase
         │       │       │       │
         └───────┴───────┴───────┘
                       │
                       │  reduce
                       ▼
                    ┌─────────┐
                    │   LLM   │──▶  final merged summary
                    └─────────┘
```

**Good for:**
- Summarising long documents
- Analysing entire codebases
- Batch classification of many items

---

## Combining Patterns

Real applications usually combine several:

```
  User query
      │
      ▼
  ┌───────────────────────────────────────────────────────┐
  │  Agent loop                                           │
  │                                                       │
  │    LLM ──▶ "retrieve relevant docs" ──▶ RAG lookup   │
  │     │                                       │         │
  │     └──────────────── chunks ───────────────┘         │
  │                                                       │
  │    LLM ──▶ "run analysis" ──▶ code execution tool     │
  │     │                                │                │
  │     └──────────── result ────────────┘                │
  │                                                       │
  │    LLM ──▶ final answer  (chain-of-thought used       │
  │                           internally for reasoning)   │
  └───────────────────────────────────────────────────────┘
```

---

## What LXC 202 Supports Today

| Pattern | How |
|---------|-----|
| Direct inference | Ollama API at `http://192.168.2.202:11434` |
| Chat / multi-turn | Open WebUI (port 3000), or any client managing message history |
| RAG | AnythingLLM (port 3001) — `nomic-embed-text` + `qwen2.5:3b` |
| Agents, chaining, map-reduce | Build on top using LangChain / LlamaIndex pointed at the Ollama API |

See [ollama-api-reference.md](ollama-api-reference.md) for connection details and client examples.

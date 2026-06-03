"""Test the Ollama API on LXC 202 (192.168.2.202).

Run:  uv run python scripts/test_ollama.py
      MODEL=analysis-assistant uv run python scripts/test_ollama.py
"""

import os
import sys

import httpx
import ollama
from rich import box
from rich.console import Console
from rich.panel import Panel
from rich.table import Table

HOST = "http://192.168.2.202:11434"
MODEL = os.getenv("MODEL", "qwen2.5:3b")
EMBED_MODEL = os.getenv("EMBED_MODEL", "nomic-embed-text")
console = Console()
client = ollama.Client(host=HOST)

PASS = "[bold green]PASS[/bold green]"
FAIL = "[bold red]FAIL[/bold red]"


def section(title: str) -> None:
    console.rule(f"[bold cyan]{title}[/bold cyan]")


def test_health() -> None:
    section("Health")
    try:
        r = httpx.get(HOST, timeout=5)
        r.raise_for_status()
        console.print(f"{PASS}  GET /  →  {r.text.strip()!r}")
    except Exception as exc:
        console.print(f"{FAIL}  GET /  →  {exc}")
        sys.exit(1)

    try:
        r = httpx.get(f"{HOST}/api/version", timeout=5)
        data = r.json()
        console.print(f"{PASS}  version: [cyan]{data.get('version', '?')}[/cyan]")
    except Exception as exc:
        console.print(f"{FAIL}  /api/version  →  {exc}")
        sys.exit(1)


def test_list_models() -> None:
    section("List Models")
    response = client.list()
    models = response.models
    if not models:
        console.print("[yellow]No models found on server.[/yellow]")
        return
    table = Table(box=box.ROUNDED, show_lines=True)
    table.add_column("Model", style="cyan")
    table.add_column("Size", justify="right", style="magenta")
    table.add_column("Family", style="dim")
    for m in models:
        size_gb = f"{m.size / 1e9:.2f} GB" if m.size else "?"
        family = (m.details.family if m.details else None) or "?"
        table.add_row(m.model, size_gb, family)
    console.print(table)
    console.print(f"{PASS}  {len(models)} model(s) listed")


def test_running_models() -> None:
    section("Running Models (VRAM)")
    response = client.ps()
    running = response.models
    if not running:
        console.print("[dim]No models currently loaded in VRAM.[/dim]")
        console.print(f"{PASS}  /api/ps reachable")
        return
    table = Table(box=box.ROUNDED, show_lines=True)
    table.add_column("Model", style="cyan")
    table.add_column("Size", justify="right", style="magenta")
    table.add_column("Expires At", style="yellow")
    for m in running:
        size_gb = f"{m.size / 1e9:.2f} GB" if m.size else "?"
        expires = str(m.expires_at)[:19].replace("T", " ") if m.expires_at else "?"
        table.add_row(m.model, size_gb, expires)
    console.print(table)
    console.print(f"{PASS}  {len(running)} model(s) in VRAM")


def test_generate() -> None:
    section(f"Generate (non-streaming) — {MODEL}")
    prompt = "Reply with exactly one sentence: what is Ollama?"
    console.print(f"Prompt: [italic]{prompt}[/italic]")
    try:
        response = client.generate(model=MODEL, prompt=prompt, stream=False)
        text = response.response.strip()
        console.print(Panel(text, expand=False))
        console.print(f"{PASS}  {response.eval_count} tokens generated")
    except ollama.ResponseError as exc:
        console.print(f"{FAIL}  {exc}")


def test_stream() -> None:
    section(f"Generate (streaming) — {MODEL}")
    prompt = "Count from 1 to 5, one number per line, nothing else."
    console.print(f"Prompt: [italic]{prompt}[/italic]")
    console.print("Response: ", end="")
    try:
        token_count = 0
        for chunk in client.generate(model=MODEL, prompt=prompt, stream=True):
            console.print(chunk.response, end="", highlight=False)
            token_count += 1
        console.print()
        console.print(f"{PASS}  {token_count} chunk(s) streamed")
    except ollama.ResponseError as exc:
        console.print(f"\n{FAIL}  {exc}")


def test_chat() -> None:
    section(f"Chat (multi-turn) — {MODEL}")
    messages = [
        {"role": "system", "content": "You are a terse assistant. Keep all replies under 20 words."},
        {"role": "user", "content": "What GPU is typically used with Ollama for local inference?"},
    ]
    try:
        response = client.chat(model=MODEL, messages=messages)
        reply = response.message.content.strip()
        console.print(Panel(reply, title="assistant", expand=False))

        messages.append({"role": "assistant", "content": reply})
        messages.append({"role": "user", "content": "And how much VRAM is recommended?"})
        response2 = client.chat(model=MODEL, messages=messages)
        reply2 = response2.message.content.strip()
        console.print(Panel(reply2, title="assistant (turn 2)", expand=False))
        console.print(f"{PASS}  2-turn chat completed")
    except ollama.ResponseError as exc:
        console.print(f"{FAIL}  {exc}")


def test_embeddings() -> None:
    section(f"Embeddings — {EMBED_MODEL}")
    text = "NVIDIA RTX 3060 GPU with 12 GB VRAM"
    try:
        response = client.embed(model=EMBED_MODEL, input=text)
        vec = response.embeddings[0]
        console.print(f"Input:  [italic]{text}[/italic]")
        console.print(f"Vector: dim=[cyan]{len(vec)}[/cyan]  first_3={[round(v, 4) for v in vec[:3]]}")
        console.print(f"{PASS}  embedding returned")
    except ollama.ResponseError as exc:
        console.print(f"{FAIL}  {exc}")


def main() -> None:
    console.print(Panel(
        f"Ollama API test suite\n"
        f"Host:        [cyan]{HOST}[/cyan]\n"
        f"Model:       [cyan]{MODEL}[/cyan]\n"
        f"Embed model: [cyan]{EMBED_MODEL}[/cyan]",
        expand=False,
    ))

    test_health()
    test_list_models()
    test_running_models()
    test_generate()
    test_stream()
    test_chat()
    test_embeddings()

    section("Done")
    console.print("[bold green]All tests completed.[/bold green]")


if __name__ == "__main__":
    main()

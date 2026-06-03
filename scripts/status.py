"""Print Ollama server status on VM 202 (192.168.2.202)."""

import json
import subprocess
import sys
import urllib.request

from rich import box
from rich.console import Console
from rich.panel import Panel
from rich.rule import Rule
from rich.table import Table

HOST = "http://192.168.2.202:11434"
VM_SSH = "ubuntu@192.168.2.202"
console = Console()


def fetch(path: str) -> dict | None:
    try:
        with urllib.request.urlopen(f"{HOST}{path}", timeout=5) as r:
            return json.loads(r.read())
    except Exception:
        return None


def fetch_gpu() -> list[dict] | None:
    try:
        result = subprocess.run(
            [
                "ssh", "-o", "StrictHostKeyChecking=no", "-o", "ConnectTimeout=5",
                VM_SSH,
                "nvidia-smi --query-gpu=name,memory.total,memory.used,memory.free,utilization.gpu,temperature.gpu --format=csv,noheader,nounits",
            ],
            capture_output=True, text=True, timeout=15,
        )
        if result.returncode != 0 or not result.stdout.strip():
            return None
        gpus = []
        for line in result.stdout.strip().splitlines():
            parts = [p.strip() for p in line.split(",")]
            if len(parts) == 6:
                gpus.append({
                    "name": parts[0],
                    "mem_total": parts[1],
                    "mem_used": parts[2],
                    "mem_free": parts[3],
                    "util": parts[4],
                    "temp": parts[5],
                })
        return gpus or None
    except Exception:
        return None


def main() -> None:
    version_data = fetch("/api/version")
    if not version_data:
        console.print(Panel(
            f"[bold red]Ollama is NOT reachable at {HOST}[/bold red]",
            expand=False,
        ))
        sys.exit(1)

    version = version_data.get("version", "?")
    console.print(Panel(
        f"[bold green]Ollama running[/bold green] on [cyan]{HOST}[/cyan] — version: [cyan]{version}[/cyan]",
        expand=False,
    ))

    gpus = fetch_gpu()
    if gpus:
        gpu_table = Table(title="GPU Status (VM 202)", box=box.ROUNDED, show_lines=True)
        gpu_table.add_column("GPU", style="bold white", no_wrap=True)
        gpu_table.add_column("Util %", justify="right", style="green")
        gpu_table.add_column("Temp °C", justify="right", style="yellow")
        gpu_table.add_column("Mem Used", justify="right", style="magenta")
        gpu_table.add_column("Mem Free", justify="right", style="cyan")
        gpu_table.add_column("Mem Total", justify="right", style="dim")
        for g in gpus:
            gpu_table.add_row(
                g["name"], g["util"], g["temp"],
                f"{g['mem_used']} MB", f"{g['mem_free']} MB", f"{g['mem_total']} MB",
            )
        console.print(gpu_table)
    else:
        console.print("[dim]Could not fetch GPU stats from VM 202 via SSH.[/dim]")

    ps_data = fetch("/api/ps")
    loaded_models = (ps_data or {}).get("models", [])
    if loaded_models:
        table = Table(title="Loaded Models", box=box.ROUNDED, show_lines=True)
        table.add_column("Model", style="bold cyan", no_wrap=True)
        table.add_column("Size", justify="right", style="magenta")
        table.add_column("Expires At", style="yellow")
        for m in loaded_models:
            size = m.get("size", 0)
            size_gb = f"{size / 1e9:.2f} GB" if size else "?"
            expires = m.get("expires_at", "")[:19].replace("T", " ") or "?"
            table.add_row(m.get("name", "?"), size_gb, expires)
        console.print(table)
    else:
        console.print("[dim]No models currently loaded in VRAM.[/dim]")

    tags_data = fetch("/api/tags")
    available = (tags_data or {}).get("models", [])
    if available:
        console.print(Rule("[bold]Available models[/bold]"))
        avail_table = Table(box=box.SIMPLE, show_header=True, header_style="bold magenta")
        avail_table.add_column("Model", style="cyan")
        avail_table.add_column("Size", justify="right")
        for m in available:
            size = m.get("size", 0)
            size_gb = f"{size / 1e9:.2f} GB" if size else "?"
            avail_table.add_row(m.get("name", "?"), size_gb)
        console.print(avail_table)


if __name__ == "__main__":
    main()

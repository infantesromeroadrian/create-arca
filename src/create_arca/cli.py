"""Thin CLI over Copier: `create-arca [DEST]` runs the wizard and renders ARCA.

We intentionally do not reimplement a prompt wizard — Copier already asks the
copier.yml questions, validates them, supports `copier update`, and handles the
template engine. This entry point just resolves where the template lives (the
installed package, or this repo in dev) and where to write (default ~/.claude),
then hands off. Keeping it thin means there is exactly one source of questions.
"""

from __future__ import annotations

import sys
from pathlib import Path

from rich.console import Console

console = Console()

# In a published wheel the template ships beside the package; in this repo it is
# two levels up. Resolve the first location that actually holds a copier.yml.
_CANDIDATES = (
    Path(__file__).resolve().parent / "template_src",       # packaged
    Path(__file__).resolve().parents[2],                     # dev checkout (repo root)
)


def _template_root() -> Path:
    for candidate in _CANDIDATES:
        if (candidate / "copier.yml").is_file():
            return candidate
    raise SystemExit("create-arca: could not locate the ARCA template (no copier.yml found)")


def main(argv: list[str] | None = None) -> int:
    """Run the ARCA generator. Optional first arg is the destination directory."""
    argv = sys.argv[1:] if argv is None else argv
    dest = Path(argv[0]).expanduser() if argv else Path.home() / ".claude"

    try:
        from copier import run_copy
    except ImportError:
        console.print("[red]create-arca requires `copier`. Install with: uvx create-arca[/red]")
        return 1

    console.rule("[bold]create-arca[/bold]")
    console.print(f"Rendering ARCA into [cyan]{dest}[/cyan]\n")
    # No unsafe=True: the template ships no Copier _tasks, so no code execution
    # is needed. Re-enable explicitly — and document it in the README — only if
    # a future template adds tasks, so users always consent to running code.
    run_copy(src_path=str(_template_root()), dst_path=str(dest))
    console.print("\n[green]Done.[/green] Open Claude Code in your destination and meet ARCA.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

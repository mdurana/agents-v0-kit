"""NWOB CLI entry point."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Optional

import typer
from rich.console import Console
from rich.table import Table

from ._artifact_paths import (
    init_mapping_from_example,
    load_mapping,
    resolve_all,
    scaffold_nwob_docs_enabled,
    validate_mapping,
)
from ._assets import repo_root
from ._bundles import VALID_PERSONAS, list_bundles, load_bundle
from ._doctor import run_doctor
from ._install import install_persona, switch_persona
from ._manifest import load_active_persona, load_manifest
from . import __version__

app = typer.Typer(
    name="nwob",
    help="Initialize NWOB agent skills with persona-scoped bundles for Cursor.",
    add_completion=False,
)
persona_app = typer.Typer(help="Manage installed personas.")
bundle_app = typer.Typer(help="Inspect persona bundles.")
app.add_typer(persona_app, name="persona")
app.add_typer(bundle_app, name="bundle")
config_app = typer.Typer(help="Configure NWOB project settings.")
app.add_typer(config_app, name="config")

console = Console()


def _resolve_project(path: Optional[Path], here: bool) -> Path:
    if here or path is None:
        return Path.cwd().resolve()
    if str(path) == ".":
        return Path.cwd().resolve()
    return path.resolve()


@app.callback()
def main(version: bool = typer.Option(False, "--version", "-V", help="Show version.")) -> None:
    if version:
        console.print(f"nwob {__version__}")
        raise typer.Exit()


@app.command("init")
def init_cmd(
    project_path: Optional[Path] = typer.Argument(
        None, help="Project directory (use '.' or --here for current directory)"
    ),
    here: bool = typer.Option(False, "--here", help="Initialize in current directory."),
    persona: str = typer.Option(
        "product-owner", "--persona", "-p", help=f"Persona bundle to install."
    ),
    integration: str = typer.Option("cursor", "--integration", "-i", help="Agent integration."),
    force: bool = typer.Option(False, "--force", help="Overwrite managed files."),
    no_scaffold_docs: bool = typer.Option(
        False,
        "--no-scaffold-docs",
        help="Skip nwob-docs/ tree scaffolding; use .nwob/artifact-paths.json for existing docs.",
    ),
) -> None:
    """Bootstrap NWOB skills in a project directory."""
    if persona not in VALID_PERSONAS:
        console.print(f"[red]Unknown persona:[/red] {persona}")
        console.print(f"Choose from: {', '.join(VALID_PERSONAS)}")
        raise typer.Exit(1)

    project = _resolve_project(project_path, here or project_path is None)
    project.mkdir(parents=True, exist_ok=True)

    console.print(f"[cyan]Initializing NWOB[/cyan] in [bold]{project}[/bold]")
    console.print(f"  Persona: {persona}")
    console.print(f"  Integration: {integration}")
    if no_scaffold_docs:
        console.print("  Docs scaffold: skipped (--no-scaffold-docs)")

    try:
        summary = install_persona(
            project,
            persona,
            integration=integration,
            force=force,
            set_active=True,
            scaffold_nwob_docs=not no_scaffold_docs,
        )
    except Exception as exc:
        console.print(f"[red]Init failed:[/red] {exc}")
        raise typer.Exit(1) from exc

    console.print("[green]Done.[/green]")
    console.print(f"  Skills installed: {summary['skills']}")
    console.print(f"  Commands: {len(summary['commands'])}")
    if no_scaffold_docs:
        console.print(
            "  Artifact paths: `.nwob/artifact-paths.json` written on init "
            "(SDD keys: required `spec`; optional `stories_dir`). "
            "Edit it to map existing docs, then run `nwob config paths --validate`."
        )
    else:
        console.print("  Next: open Cursor and run a persona command (e.g. `/problem`).")
        console.print(
            "  Artifact paths: `.nwob/artifact-paths.json` written on init "
            "(SDD defaults; edit if your docs live elsewhere)."
        )


@persona_app.command("add")
def persona_add(
    persona_id: str = typer.Argument(help="Persona bundle id to add."),
    project_path: Optional[Path] = typer.Option(None, "--project", help="Project path."),
    force: bool = typer.Option(False, "--force", help="Overwrite managed files."),
) -> None:
    """Add another persona bundle (additive)."""
    if persona_id not in VALID_PERSONAS:
        console.print(f"[red]Unknown persona:[/red] {persona_id}")
        raise typer.Exit(1)

    project = _resolve_project(project_path, project_path is None)
    if not (project / ".nwob").is_dir():
        console.print("[red]Not an NWOB project.[/red] Run `nwob init` first.")
        raise typer.Exit(1)

    summary = install_persona(project, persona_id, force=force, set_active=False)
    manifest = load_manifest(project)
    update_active = load_active_persona(project).get("persona") or persona_id
    from ._agents_overlay import update_agents_md

    update_agents_md(project, update_active, manifest["installed_personas"])
    console.print(
        f"[green]Registered persona[/green] {persona_id} — "
        f"run `nwob persona switch {persona_id}` to install cursor assets"
    )


@persona_app.command("switch")
def persona_switch(
    persona_id: str = typer.Argument(help="Persona to activate."),
    project_path: Optional[Path] = typer.Option(None, "--project", help="Project path."),
) -> None:
    """Switch the active persona."""
    project = _resolve_project(project_path, project_path is None)
    try:
        switch_persona(project, persona_id)
    except ValueError as exc:
        console.print(f"[red]{exc}[/red]")
        raise typer.Exit(1) from exc
    console.print(f"[green]Active persona:[/green] {persona_id}")


@persona_app.command("list")
def persona_list(
    project_path: Optional[Path] = typer.Option(None, "--project", help="Project path."),
) -> None:
    """List installed and active personas."""
    project = _resolve_project(project_path, project_path is None)
    manifest = load_manifest(project)
    installed = manifest.get("installed_personas", [])
    active = load_active_persona(project).get("persona", "(none)")

    table = Table(title="NWOB Personas")
    table.add_column("Persona")
    table.add_column("Status")
    for pid in installed:
        status = "active" if pid == active else "installed"
        table.add_row(pid, status)
    for pid in VALID_PERSONAS:
        if pid not in installed:
            table.add_row(pid, "not installed")
    console.print(table)
    console.print(f"Active: [bold]{active}[/bold]")


@bundle_app.command("list")
def bundle_list() -> None:
    """List available persona bundles."""
    for bid in list_bundles():
        bundle = load_bundle(bid)
        meta = bundle.get("bundle", {})
        console.print(f"  [cyan]{bid}[/cyan] — {meta.get('name', bid)}")


@bundle_app.command("info")
def bundle_info(
    persona_id: str = typer.Argument(help="Bundle id."),
    json_output: bool = typer.Option(False, "--json", help="JSON output."),
) -> None:
    """Show bundle contents."""
    bundle = load_bundle(persona_id)
    if json_output:
        console.print(json.dumps(bundle, indent=2))
        return

    meta = bundle.get("bundle", {})
    provides = bundle.get("provides", {})
    console.print(f"[bold]{meta.get('name')}[/bold] ({persona_id})")
    console.print(meta.get("description", ""))
    console.print("\nSkills:")
    for s in provides.get("skills", []):
        console.print(f"  - {s}")
    console.print("\nCommands:")
    for c in provides.get("commands", []):
        console.print(f"  - /{c['name']}")
    console.print("\nTemplates:")
    for t in provides.get("templates", []):
        console.print(f"  - {t}")


@config_app.command("paths")
def config_paths(
    project_path: Optional[Path] = typer.Option(None, "--project", help="Project path."),
    show: bool = typer.Option(False, "--show", help="Print resolved artifact paths."),
    validate: bool = typer.Option(False, "--validate", help="Validate mapping file."),
    init: bool = typer.Option(
        False,
        "--init",
        help="Create .nwob/artifact-paths.json with SDD defaults if missing.",
    ),
    force: bool = typer.Option(False, "--force", help="Overwrite existing mapping file."),
) -> None:
    """Manage local SDD artifact path mapping (.nwob/artifact-paths.json, gitignored)."""
    project = _resolve_project(project_path, project_path is None)

    if not any([show, validate, init]):
        show = True

    if init:
        try:
            dest = init_mapping_from_example(project, force=force)
        except FileNotFoundError as exc:
            console.print(f"[red]{exc}[/red]")
            raise typer.Exit(1) from exc
        if dest is None:
            console.print("[yellow]Mapping file already exists[/yellow] — use --force to overwrite.")
        else:
            console.print(f"[green]Created[/green] {dest.relative_to(project)}")
            console.print(
                "Edit required `spec` (optional `stories_dir`); remove obsolete "
                "`plan`/`tasks` keys and other non-SDD keys. Then run "
                "`nwob config paths --validate`."
            )

    if show:
        mapping = load_mapping(project)
        table = Table(title="Resolved artifact paths")
        table.add_column("Key")
        table.add_column("Path")
        table.add_column("Source")
        for key, abs_path in resolve_all(project).items():
            rel = str(abs_path.relative_to(project))
            source = "mapping" if key in mapping else "default"
            table.add_row(key, rel, source)
        console.print(table)
        if not scaffold_nwob_docs_enabled(project):
            console.print("[dim]Init option: scaffold_nwob_docs=false[/dim]")

    if validate:
        errors, warnings = validate_mapping(project)
        for warning in warnings:
            console.print(f"[yellow]Warning:[/yellow] {warning}")
        if errors:
            console.print("[red]Validation failed:[/red]")
            for error in errors:
                console.print(f"  - {error}")
            raise typer.Exit(1)
        if not errors and not warnings:
            console.print("[green]Artifact path mapping is valid.[/green]")


@app.command("doctor")
def doctor_cmd(
    project_path: Optional[Path] = typer.Option(None, "--project", help="Project path."),
) -> None:
    """Verify NWOB project installation."""
    project = _resolve_project(project_path, project_path is None)
    ok, issues = run_doctor(project)
    if ok:
        if any(msg.startswith("[warning]") for msg in issues):
            console.print("[yellow]NWOB project is healthy with warnings:[/yellow]")
            for issue in issues:
                console.print(f"  - {issue}")
        else:
            console.print("[green]NWOB project is healthy.[/green]")
        raise typer.Exit(0)
    console.print("[red]Issues found:[/red]")
    for issue in issues:
        console.print(f"  - {issue}")
    raise typer.Exit(1)


@app.command("root")
def root_cmd() -> None:
    """Print resolved nwob-agent-skills root (debug)."""
    console.print(str(repo_root()))


if __name__ == "__main__":
    app()

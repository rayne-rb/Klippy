#!/usr/bin/env python3
"""Regenerate Klippy.sln from the Godot projects in the repository root.

Godot/GDScript projects are not MSBuild projects, so the solution is built from
solution folders that list each project's files. Run this after adding a project
or a new source file so the Solution view stays in sync:

    python3 tools/regen-solution.py

Existing solution folder GUIDs are preserved so Rider keeps per-folder state.
"""

import pathlib
import re
import uuid

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOLUTION = ROOT / "Klippy.sln"
SOLUTION_FOLDER_TYPE = "{2150E333-8FDC-42A3-9474-1A3956D46DE8}"
ROOT_ITEMS = (".editorconfig", ".gitignore", "README.md")
SKIP_SUFFIXES = (".uid",)  # Godot-generated sidecars; they only clutter the tree


def new_guid():
    return "{" + str(uuid.uuid4()).upper() + "}"


def existing_guids():
    """Map solution folder name -> GUID from the current solution, if any."""
    if not SOLUTION.exists():
        return {}, None
    text = SOLUTION.read_text(encoding="utf-8")
    folders = dict(
        re.findall(
            r'^Project\("\{2150E333-8FDC-42A3-9474-1A3956D46DE8\}"\) = '
            r'"([^"]+)", "[^"]+", "(\{[0-9A-Fa-f-]+\})"',
            text,
            re.MULTILINE,
        )
    )
    solution_guid = re.search(r"SolutionGuid = (\{[0-9A-Fa-f-]+\})", text)
    return folders, solution_guid.group(1) if solution_guid else None


def project_files(project_dir):
    return [
        f"{project_dir.name}\\{f.name}"
        for f in sorted(project_dir.iterdir())
        if f.is_file()
        and not f.name.startswith(".")
        and f.suffix not in SKIP_SUFFIXES
    ]


def folder(name, items, guid):
    lines = [f'Project("{SOLUTION_FOLDER_TYPE}") = "{name}", "{name}", "{guid}"']
    lines.append("\tProjectSection(SolutionItems) = preProject")
    lines.extend(f"\t\t{item} = {item}" for item in items)
    lines.append("\tEndProjectSection")
    lines.append("EndProject")
    return lines


def main():
    known, solution_guid = existing_guids()
    guid_for = lambda name: known.get(name) or new_guid()

    lines = [
        "Microsoft Visual Studio Solution File, Format Version 12.00",
        "# Visual Studio Version 17",
        "VisualStudioVersion = 17.0.31903.59",
        "MinimumVisualStudioVersion = 10.0.40219.1",
    ]

    lines += folder(
        "Solution Items",
        [f for f in ROOT_ITEMS if (ROOT / f).exists()],
        guid_for("Solution Items"),
    )

    projects = sorted(p.parent for p in ROOT.glob("*/project.godot"))
    for project in projects:
        lines += folder(project.name, project_files(project), guid_for(project.name))

    lines += [
        "Global",
        "\tGlobalSection(SolutionProperties) = preSolution",
        "\t\tHideSolutionNode = FALSE",
        "\tEndGlobalSection",
        "\tGlobalSection(ExtensibilityGlobals) = postSolution",
        f"\t\tSolutionGuid = {solution_guid or new_guid()}",
        "\tEndGlobalSection",
        "EndGlobal",
        "",
    ]

    SOLUTION.write_text("\n".join(lines), encoding="utf-8")
    print(f"Wrote {SOLUTION.name}: {', '.join(p.name for p in projects) or 'no projects found'}")


if __name__ == "__main__":
    main()

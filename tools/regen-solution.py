#!/usr/bin/env python3
"""Regenerate Klippy.sln from what is actually on disk.

The solution holds two different kinds of thing:

* MSBuild projects (Klippy.Server, Klippy.Shared, Klippy.Mobile) which are
  referenced normally and carry build configurations.
* Godot projects (Klippy.Companion) which are not MSBuild projects at all, so they
  appear as solution folders listing their files. That listing does not maintain
  itself, which is why this script exists.

Godot projects are mirrored folder for folder, so the feature slices show up in the
Solution view the way they do on disk. Run it after adding a project, a slice or a
source file:

    python3 tools/regen-solution.py

Existing GUIDs are reused so Rider keeps per-folder and per-project state.
"""

import pathlib
import re
import uuid

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOLUTION = ROOT / "Klippy.sln"

SOLUTION_FOLDER_TYPE = "{2150E333-8FDC-42A3-9474-1A3956D46DE8}"
CSHARP_PROJECT_TYPE = "{FAE04EC0-301F-11D3-BF4B-00C04F79EFBC}"

ROOT_ITEMS = (".editorconfig", ".gitignore", "README.md")
SKIP_SUFFIXES = (".uid",)          # Godot sidecars; they only clutter the tree
SKIP_DIRS = {".godot", ".idea", "bin", "obj", "android"}
CONFIGURATIONS = ("Debug", "Release")


def new_guid():
    return "{" + str(uuid.uuid4()).upper() + "}"


def existing_state():
    """Reuse the GUIDs already in the solution so Rider keeps its state."""
    if not SOLUTION.exists():
        return {}, {}, None

    text = SOLUTION.read_text(encoding="utf-8")
    # A folder entry's "path" is its position in the tree, so name alone is not
    # unique once slices nest; key on both.
    folders = {
        f"{name}|{path}": guid
        for name, path, guid in re.findall(
            r'^Project\("\{2150E333-8FDC-42A3-9474-1A3956D46DE8\}"\) = '
            r'"([^"]+)", "([^"]+)", "(\{[0-9A-Fa-f-]+\})"',
            text,
            re.MULTILINE,
        )
    }
    projects = {
        path.replace("\\", "/"): guid
        for _name, path, guid in re.findall(
            r'^Project\("\{FAE04EC0-301F-11D3-BF4B-00C04F79EFBC\}"\) = '
            r'"([^"]+)", "([^"]+)", "(\{[0-9A-Fa-f-]+\})"',
            text,
            re.MULTILINE,
        )
    }
    solution_guid = re.search(r"SolutionGuid = (\{[0-9A-Fa-f-]+\})", text)
    return folders, projects, solution_guid.group(1) if solution_guid else None


FOLDER_GUIDS, PROJECT_GUIDS, SOLUTION_GUID = existing_state()


def folder_guid(name, key):
    return FOLDER_GUIDS.get(f"{name}|{key}") or new_guid()


def emit_folder(name, key, items, guid):
    lines = [f'Project("{SOLUTION_FOLDER_TYPE}") = "{name}", "{key}", "{guid}"']
    if items:
        lines.append("\tProjectSection(SolutionItems) = preProject")
        lines.extend(f"\t\t{item} = {item}" for item in items)
        lines.append("\tEndProjectSection")
    lines.append("EndProject")
    return lines


def walk_godot_project(directory, relative_to, nested, lines, parent_guid=None):
    """Mirror a Godot project's folders as nested solution folders."""
    files = sorted(
        f for f in directory.iterdir()
        if f.is_file() and not f.name.startswith(".") and f.suffix not in SKIP_SUFFIXES
    )
    items = [str(f.relative_to(relative_to.parent)).replace("/", "\\") for f in files]

    name = directory.name
    key = str(directory.relative_to(ROOT)).replace("/", "\\")
    guid = folder_guid(name, key)

    lines += emit_folder(name, key, items, guid)
    if parent_guid:
        nested.append((guid, parent_guid))

    for child in sorted(d for d in directory.iterdir() if d.is_dir()):
        if child.name in SKIP_DIRS or child.name.startswith("."):
            continue
        walk_godot_project(child, relative_to, nested, lines, guid)


def main():
    lines = [
        "Microsoft Visual Studio Solution File, Format Version 12.00",
        "# Visual Studio Version 17",
        "VisualStudioVersion = 17.0.31903.59",
        "MinimumVisualStudioVersion = 10.0.40219.1",
    ]
    nested = []

    lines += emit_folder(
        "Solution Items",
        "Solution Items",
        [f for f in ROOT_ITEMS if (ROOT / f).exists()],
        folder_guid("Solution Items", "Solution Items"),
    )

    godot_projects = sorted(p.parent for p in ROOT.glob("*/project.godot"))
    for project in godot_projects:
        walk_godot_project(project, project, nested, lines)

    csproj_files = sorted(ROOT.glob("*/*.csproj"))
    project_entries = []
    for csproj in csproj_files:
        name = csproj.stem
        relative = str(csproj.relative_to(ROOT)).replace("/", "\\")
        guid = PROJECT_GUIDS.get(relative.replace("\\", "/")) or new_guid()
        project_entries.append((name, guid))
        lines.append(f'Project("{CSHARP_PROJECT_TYPE}") = "{name}", "{relative}", "{guid}"')
        lines.append("EndProject")

    lines.append("Global")
    lines.append("\tGlobalSection(SolutionConfigurationPlatforms) = preSolution")
    for configuration in CONFIGURATIONS:
        lines.append(f"\t\t{configuration}|Any CPU = {configuration}|Any CPU")
    lines.append("\tEndGlobalSection")

    lines.append("\tGlobalSection(ProjectConfigurationPlatforms) = postSolution")
    for _name, guid in project_entries:
        for configuration in CONFIGURATIONS:
            lines.append(f"\t\t{guid}.{configuration}|Any CPU.ActiveCfg = {configuration}|Any CPU")
            lines.append(f"\t\t{guid}.{configuration}|Any CPU.Build.0 = {configuration}|Any CPU")
    lines.append("\tEndGlobalSection")

    lines.append("\tGlobalSection(SolutionProperties) = preSolution")
    lines.append("\t\tHideSolutionNode = FALSE")
    lines.append("\tEndGlobalSection")

    if nested:
        lines.append("\tGlobalSection(NestedProjects) = preSolution")
        for child, parent in nested:
            lines.append(f"\t\t{child} = {parent}")
        lines.append("\tEndGlobalSection")

    lines.append("\tGlobalSection(ExtensibilityGlobals) = postSolution")
    lines.append(f"\t\tSolutionGuid = {SOLUTION_GUID or new_guid()}")
    lines.append("\tEndGlobalSection")
    lines.append("EndGlobal")
    lines.append("")

    SOLUTION.write_text("\n".join(lines), encoding="utf-8")
    print(
        f"Wrote {SOLUTION.name}: "
        f"{len(godot_projects)} Godot project(s), {len(project_entries)} MSBuild project(s)"
    )


if __name__ == "__main__":
    main()

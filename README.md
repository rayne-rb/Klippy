# Klippy

A Rider solution holding several standalone Godot projects. Each top-level folder
is its own Godot project with its own `project.godot`.

## Projects

| Project | Description |
| --- | --- |
| [Klippy.Companion](Klippy.Companion/README.md) | Clippy-inspired desktop pet — a small rock that lives on your desktop |

## Working on it

- **Rider** — open `Klippy.sln`. Each project appears as a solution folder; the
  *File System* view in Solution Explorer shows everything on disk.
- **Godot editor** — open the project folder directly (e.g. `Klippy.Companion`),
  not the repository root.

Godot/GDScript projects are not MSBuild projects, so `Klippy.sln` is made of
solution folders that list each project's files rather than referencing `.csproj`
files. That listing does not update itself — after adding a project or a new
source file, run:

```sh
python3 tools/regen-solution.py
```

## Adding a project

1. Create the new Godot project in its own folder at the repository root.
2. Run `python3 tools/regen-solution.py` to pick it up.
3. Add it to the table above.

The root `.gitignore` and `.editorconfig` apply to every project, so per-project
copies are only needed for project-specific rules.

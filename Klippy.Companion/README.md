# Klippy

Klippy is a Clippy-inspired desktop pet — a small rock that lives on your desktop.

## Requirements

- Godot Engine **4.7** 
- Linux or Windows (not tested/targeted on macOS)

## Features

- Drag and throw Klippy with real physics, allowing him to interact with the desktop
- Food, mood, and health stats: feeding, passive healing, starvation, death, and revival
- Right-click menu: Feed, Status, DVD mode, Settings, Close (plus Revive / Dev Tools when relevant)
- State persists across launches, including offline progress while closed
- Dev Tools panel (enable in Settings) for nudging stats directly while testing

## Exporting

Klippy does not work properly when run through the Godot editor, so you'll need to export it to a binary.

1. Editor > Manage Export Templates — install templates matching your installed Godot version if you haven't already.
2. Project > Export, add a Linux or Windows preset.
3. Select an export directory and click "Export"
4. Run the resulting binary directly


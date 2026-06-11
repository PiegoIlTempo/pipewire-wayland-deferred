# OBS PipeWire Deferred Source Activation

Eliminates window selection dialogs at OBS startup on **Wayland/KDE**. PipeWire screen capture sources are created in a "deferred" state and automatically activated when the target window (game) opens, via `kdotool` detection.

## The Problem

On Wayland with KDE Plasma, when OBS loads its scenes at startup, it calls `xdg-desktop-portal` (`CreateSession`) for **every** window capture source. If the target window (game, launcher, etc.) isn't open yet, the portal shows a dialog asking which window to capture — every single time.

Even after ticking "Allow restoring in future sessions", the saved token doesn't always prevent the dialog from reappearing (window not yet present, stale token, resolution changes, etc.).

## The Solution

A patch to OBS's `linux-pipewire` plugin that **defers** portal session creation for **all** sources at startup. The session is only created when:

1. An **IPC trigger file** (`/tmp/obs-trigger-<source_name>`) is written
2. The **Lua script** detects the target window via `kdotool` and forces an `update()` on the source

If the window was already configured in a previous session (has a `restore_token`), the portal restores the session **silently** — no dialog.

### Components

| File | Role |
|---|---|
| `screencast-portal.c` (patched) | Modified C plugin — defer at startup, IPC trigger, "Reload" button works |
| `auto-restore.lua` | OBS Lua script — polls kdotool every 3s, writes IPC trigger files |
| `build.sh` | Build script for the patched plugin |

## Installation

### Prerequisites (Fedora)

```bash
sudo dnf install gcc obs-studio-devel pipewire-devel libdrm-devel \
  extra-cmake-modules glib2-devel
```

For other distros, install the equivalent development packages.

### Build & Install the Plugin

```bash
git clone https://github.com/PiegoIlTempo/pipewire-wayland-deferred
cd pipewire-wayland-deferred
./build.sh

# Backup original and install patched plugin
sudo cp /usr/lib64/obs-plugins/linux-pipewire.so{,.bak}
sudo cp /tmp/linux-pipewire.so /usr/lib64/obs-plugins/linux-pipewire.so
```

### Lua Script

1. Open OBS → **Tools → Scripts** → **+**
2. Select `auto-restore.lua`
3. Check OBS log for "auto-restore loaded"

## How window detection works

The Lua script does not use a hardcoded list of window titles. Instead, it:

1. Scans all PipeWire screen capture sources that have a `RestoreToken` (i.e., were configured at least once)
2. Takes the source name and strips common suffixes (` Video`, ` Window`, ` Capture`, ` Source`) to generate possible window titles
3. Checks each candidate against `kdotool search --name`

**Important**: name your OBS sources so they contain the target window title. For example, if your window is titled `"MyGame"`, name the source `"MyGame Video"` or just `"MyGame"`. If the source is named something generic like `"Cattura schermo (PipeWire)"`, the match will fail.

Check the OBS log for `[auto-restore]` entries to see which sources were detected.

### First-Time Setup

For each window you want to capture:

1. **First session**: open the target window, then click **"Select" / "Reload"** on the source in OBS → select the window and tick **"Allow restoring in future sessions"** → the token is saved
2. **Subsequent sessions**: open OBS first (no dialogs), then launch the target window → the Lua script detects it within 3 seconds → the portal session is restored silently

## Restoring the Original Plugin

```bash
sudo cp /usr/lib64/obs-plugins/linux-pipewire.so.bak /usr/lib64/obs-plugins/linux-pipewire.so
```

## License

GPL-2.0-or-later. This is a derivative work of OBS Studio's `linux-pipewire` plugin (Copyright 2022 Georges Basile Stavracas Neto), licensed under GPLv2+.
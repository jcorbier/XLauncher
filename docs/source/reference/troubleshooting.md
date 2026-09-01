# Troubleshooting & FAQ

## Frequently Asked Questions

### Why use a Central Data Folder instead of putting files directly in X-Plane?
1. **Profile switching**: Enables and disables large add-ons in seconds via symlinks without duplicating files.
2. **Safety during X-Plane updates**: Prevents add-on files from being modified or removed during simulator updates or clean reinstalls.
3. **Storage flexibility**: Allows storing add-ons on a secondary drive while keeping X-Plane on your system drive.

---

## Troubleshooting

### "Configure X-Plane Path" or Launch Button Disabled
- Open **Settings**.
- Make sure the **X-Plane Location** field points to the root X-Plane 12 directory containing `X-Plane.app`. A green indicator will confirm when detected.

### Add-ons in Storage Folders Not Showing or Marked Offline
- Verify that your subfolder names match the expected names:
  - `Aircraft/`
  - `Plugins/`
  - `Scenery/`
  - `LuaScripts/`
- Ensure each add-on is placed in its own subfolder (for example, `Aircraft/Zibo_737/`, not loose `.acf` files directly in `Aircraft/`).
- If storing on an external drive, ensure the drive is mounted. If a drive is unmounted, add-ons will show as **Offline** until reconnected.

### Scenery Appears Out of Order or Hidden by Default Terrain
- Go to the **Scenery** tab and drag custom airport entries towards the top of the list, above global meshes and orthophotos.
- Ensure that `scenery_packs.ini` in `<X-Plane 12>/Custom Scenery/` is writable.
- Use the **X-Plane Logs** analyzer to check for missing scenery library dependencies or corrupted scenery definitions.

### Pre-Launch Scripts Not Running
- Verify that the script has executable permissions (`chmod +x /path/to/script.sh`).
- Confirm that the script begins with a valid shebang (e.g. `#!/bin/bash` or `#!/usr/bin/env python3`).
- Check that all required environment variables are set in **Settings > Script Environment** or in the profile's **Profile Scripts** tab.

### Restoring Original CSL Lighting
- Toggle **Apply modern X-Plane 12 lighting** off in **Settings > X-CSL Models**.
- X-Plane Launcher retains `.bak` files of the original `.obj` models. You can also click **Reinstall** on any package in the **CSL** tab to redownload stock model files.

---

## Diagnostic Logs

- **X-Plane Log Analyzer**: Open the built-in simulator log analyzer by choosing **File > X-Plane Logs...** or pressing <kbd>⇧⌘L</kbd> (or selecting **X-Plane Logs** in the sidebar). It categorizes crashes, missing scenery assets, SASL/Lua script errors, and loading bottlenecks from `Log.txt`.
- **Application Logs Window**: Open the launcher application log viewer by choosing **Window > Logs...** or pressing <kbd>⌥⌘L</kbd>. This window provides real-time logs for launcher background tasks (profiles, scenery, plugins, updates, symlinks, and navigation data).
- **Updates & CSL Operations**: Click the **Console** button in the Updates or CSL tabs to view real-time operation logs and progress messages.

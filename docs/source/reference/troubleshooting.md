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

### Add-ons in Central Data Folder Not Showing in Lists
- Verify that your subfolder names match the expected names:
  - `Aircraft/`
  - `Plugins/`
  - `Scenery/`
  - `LuaScripts/`
- Ensure each add-on is placed in its own subfolder (for example, `Aircraft/Zibo_737/`, not loose `.acf` files directly in `Aircraft/`).
- If storing on an external drive, ensure the drive is mounted with read/write permissions before launching the app.

### Scenery Appears Out of Order or Hidden by Default Terrain
- Go to the **Scenery** tab and drag custom airport entries towards the top of the list, above global meshes and orthophotos.
- Ensure that `scenery_packs.ini` in `<X-Plane 12>/Custom Scenery/` is writable.

### Pre-Launch Scripts Not Running
- Verify that the script has executable permissions (`chmod +x /path/to/script.sh`).
- Confirm that the script begins with a valid shebang (e.g. `#!/bin/bash` or `#!/usr/bin/env python3`).
- Check that all required environment variables are set in **Settings > Script Environment** or in the profile's **Profile Scripts** tab.

### Restoring Original CSL Lighting
- Toggle **Apply modern X-Plane 12 lighting** off in **Settings > X-CSL Models**.
- X-Plane Launcher retains `.bak` files of the original `.obj` models. You can also click **Reinstall** on any package in the **CSL** tab to redownload stock model files.

---

## Diagnostic Logs

- **Updates & CSL Operations**: Click the **Console** button in the Updates or CSL tabs to view real-time logs and error messages.
- **Simulator Log**: Check `<X-Plane 12>/Log.txt` for general X-Plane startup and plugin diagnostic information.

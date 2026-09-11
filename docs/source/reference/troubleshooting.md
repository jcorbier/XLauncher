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

### Missing Scenery Libraries or Plugins Not Loading on Apple Silicon
- Open **Diagnostics** from the sidebar (or press <kbd>⇧⌘D</kbd>).
- In the **Add-on Integrity** tab, the launcher automatically scans for:
  - Missing community scenery libraries (OpenSceneryX, MisterX, SAM, etc.) and provides direct download links or one-click disable actions.
  - Plugin binaries that lack native Apple Silicon (`arm64`) slices on M-series Macs.
  - Broken symlinks pointing to nonexistent files.

### XLauncher Pro License Activation Issues
- **Machine limit reached (3/3)**: Each lifetime license permits activation on up to 3 personal Macs. To move an activation, open **Settings > Licensing & Edition** on an activated Mac and click **Deactivate Machine...**.
- **Invalid License File or Key**: Verify that `xlauncher.lic` has not been edited or truncated. Ensure your Mac's system clock is set to automatic network time.

### Map & Telemetry Shows "Disconnected" or "Offline"
- Confirm X-Plane 12 is running and has fully loaded into a flight.
- Check that X-Plane's built-in Web Server is active on port `8086`.
- In XLauncher, go to **Settings > X-Plane Network Settings**, verify the host is `127.0.0.1` and port is `8086`, then click **Test Connection**.

### SimBrief Import Fails
- Ensure your SimBrief **Username** or numeric **Pilot ID** is configured in **Settings > SimBrief Configuration**.
- Verify that you have generated an Operational Flight Plan (OFP) on [simbrief.com](https://www.simbrief.com). SimBrief only serves the most recent generated plan.

### Menu Bar Companion Icon Not Visible
- In **Settings > Simulator Launch & Companion Mode**, verify that **When X-Plane launches** is set to **Minimize to Menu Bar (Companion Mode)**.
- On MacBooks with a display camera notch, macOS may hide status icons if the menu bar is crowded. Close other menu bar utilities or expand the menu area.


---

## Diagnostic Tools & Logs

- **Add-on & System Diagnostics**: Open **Diagnostics** from the sidebar (<kbd>⇧⌘D</kbd>) to inspect add-on integrity, analyze disk usage and clean caches, or inspect session crash logs.
- **X-Plane Log Analyzer**: Directly access log diagnostics via **File > X-Plane Logs...** (<kbd>⇧⌘L</kbd>). It categorizes crashes, missing scenery assets, SASL/Lua script errors, and loading bottlenecks from `Log.txt`.
- **Application Logs Window**: Open the launcher application log viewer by choosing **Window > Logs...** or pressing <kbd>⌥⌘L</kbd>. This window provides real-time logs for launcher background tasks (profiles, scenery, plugins, updates, symlinks, and navigation data).
- **Updates & CSL Operations**: Click the **Console** button in the Updates or CSL tabs to view real-time operation logs and progress messages.

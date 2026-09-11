# Menu Bar Companion & Process Monitor

X-Plane Launcher includes an optional **Menu Bar Companion Mode** and simulator process monitor that runs in the macOS menu bar while X-Plane 12 is active.

---

## Overview

When X-Plane launches, XLauncher can automatically hide its main window and minimize to a lightweight companion item in the macOS menu bar (`airplane.circle.fill`).

The companion monitor:
- Tracks whether X-Plane is currently running and monitors its process PID.
- Displays elapsed flight time directly in the menu.
- Displays the currently active profile name.
- Provides one-click access to simulator files and logs without having to reopen the main window.

---

## Menu Bar Actions

Clicking the menu bar icon displays the companion menu:

- **Status Header**: Displays current X-Plane execution state and elapsed session duration (e.g. `✈️ X-Plane 12: Running (01:42:15)`).
- **Active Profile**: Shows the name of the profile loaded for the current flight session.
- **Show X-Plane Launcher (<kbd>⌘O</kbd>)**: Restores and focuses the main launcher window.
- **Open Log.txt**: Opens `<X-Plane 12>/Log.txt` in your default text editor for real-time inspection.
- **Open Output Folder...**: Reveals `<X-Plane 12>/Output` in Finder (quick access to screenshots, flight plans, and situational saves).
- **Force Quit X-Plane**: Terminates the X-Plane process immediately if the simulator hangs or becomes unresponsive.
- **Quit XLauncher (<kbd>⌘Q</kbd>)**: Exits the launcher application completely.

---

## Configuring Launch Behavior

Launch and exit behaviors can be configured in **Settings > Simulator Launch & Companion Mode**:

### When X-Plane Launches
- **Minimize to Menu Bar (Companion Mode)** *(Default)*: Hides the main window and activates the menu bar companion icon.
- **Keep XLauncher Window Open**: Keeps the main window visible on your desktop alongside the simulator.
- **Quit XLauncher Immediately**: Quits the launcher application as soon as the X-Plane process starts.

### When X-Plane Exits (Companion Mode)
- **Reopen XLauncher Window** *(Default)*: Restores the main launcher window to the screen as soon as X-Plane finishes running.
- **Quit XLauncher**: Closes the companion monitor and quits XLauncher when X-Plane exits.

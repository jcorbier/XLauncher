# Quickstart

This guide covers initial setup and creating your first profile.

---

## Welcome Assistant

When opening X-Plane Launcher for the first time, a setup assistant helps configure your simulator folder and data directory:

```{image} /_static/images/welcome-assistant.png
:alt: Screenshot of the Welcome Assistant window showing X-Plane 12 Installation and Central Data Folder paths
:align: center
```

1. **X-Plane 12 Installation**: Click **Browse** and select the folder containing `X-Plane.app` (e.g. `/Applications/X-Plane 12`). A green indicator confirms when X-Plane 12 is detected.
2. **Central Data Folder**: By default, this is set to:
   ```text
   ~/Library/Application Support/XPlaneLauncher/
   ```
   You can change this to any folder on an internal or external drive.

Click **Get Started** to finish setup.

```{tip}
You can reopen this assistant at any time from **Settings > General > Show Welcome Screen...**.
```

---

## Add-on Storage Layout

Place your add-on folders into their corresponding subdirectories in your Central Data Folder:

```text
~/Library/Application Support/XPlaneLauncher/
├── Aircraft/       # Put aircraft folders here
├── Plugins/        # Put plugin folders here
├── Scenery/        # Put custom scenery pack folders here
└── LuaScripts/     # Put .lua scripts or script folders here
```

When you enable items in X-Plane Launcher, symlinks are created in your X-Plane 12 directory:
- `<X-Plane 12>/Aircraft/`
- `<X-Plane 12>/Resources/plugins/`
- `<X-Plane 12>/Custom Scenery/`
- `<X-Plane 12>/Resources/plugins/FlyWithLua/Scripts/`

---

## Creating a Profile

1. Click the **Profile** dropdown at the top of the window and select **New Profile...** (or click `+`).
2. Enter a name (for example, `Airliner` or `VATSIM`).
3. Select the items you want active for this profile:
   - In **Aircraft**, enable the aircraft you plan to fly.
   - In **Plugins**, enable relevant plugins.
   - In **Scenery**, enable and organize your scenery packs.
   - In **Lua Scripts**, toggle your FlyWithLua scripts.
4. Click **Save** if the modified indicator appears.

---

## Launching X-Plane

Click **Launch X-Plane** at the bottom of the window:
- Any pre-launch scripts attached to the active profile run first.
- Symlinks in your X-Plane directory are updated to match your profile.
- `scenery_packs.ini` is updated with your scenery order and enabled state.
- `X-Plane.app` starts, and the launcher exits.

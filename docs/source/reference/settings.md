# Settings

This page details the options available in the **Settings** view.

```{image} /_static/images/settings-view.png
:alt: Screenshot of the Settings view with General, X-CSL Models, and Script Environment sections
:align: center
```

---

## General

- **X-Plane Location**: The folder containing your X-Plane 12 installation (where `X-Plane.app` is located). Click the folder button to change the path.
- **Central Data Folder**: The primary folder where source add-ons are stored. Defaults to `~/Library/Application Support/XPlaneLauncher/`.
- **Welcome Guide**: Click **Show Welcome Screen...** to reopen the initial setup assistant.

---

## Storage Pools & Multi-Drive Data Folders

Configure multiple storage locations across internal and external/Thunderbolt drives:

- **Add Storage Pool...**: Add an additional source directory on any mounted volume.
- **Primary**: Set which pool acts as the default destination for new add-ons.
- **Default Categories**: Assign specific add-on categories (Aircraft, Plugins, Scenery, Lua Scripts) to a pool.
- **Drive Metrics**: Displays current mount status, volume name, and available disk capacity.
- **Edit / Delete**: Rename a pool, update its category assignments, or remove the pool reference (files on disk remain intact).

---

## Automatic Updates

Configure which components automatically check for new versions and updates when X-Plane Launcher starts:

- **X-Plane Launcher application**: When enabled, checks GitHub for new application versions on startup.
- **SkunkCrafts add-ons**: When enabled, queries remote servers for updates to SkunkCrafts-managed add-ons on startup.
- **X-Updater add-ons**: When enabled, queries remote servers for updates to X-Updater-managed add-ons on startup.
- **X-CSL models**: When enabled, synchronizes the package index and checks for model updates from the X-CSL repository on startup (available when X-CSL support is enabled).
- **Navigation data (Navigraph)**: When enabled, checks Navigraph for newly published AIRAC cycles on startup (available when Navigation Data support is enabled).

:::{note}
Disabling automatic checks on launch does not prevent manual checks. You can still check for updates at any time from the **Updates**, **CSL**, **Navigation Data**, or **Settings** tabs.
:::

---

## Application Updates

- **Include pre-release and beta versions**: When enabled, checks for pre-release and beta builds on GitHub in addition to stable releases.
- **Check Now**: Manually checks GitHub for application updates immediately.
- **What's New / Update & Relaunch**: View version release notes and changelogs, or update and relaunch the application in-place directly from the UI (with a manual `.dmg` download option available as a fallback).

---

## X-CSL Models

- **Enable X-CSL support**: Adds the CSL tab to the sidebar for managing multiplayer aircraft models in `<X-Plane 12>/Resources/plugins/IVAO_CSL/CSL`.
- **Apply modern X-Plane 12 lighting to X-CSL models**: Injects photometric parameterized lighting, ground spill, dynamic strobe sequences, and gear-coupled taxi light animations into installed CSL aircraft models.

---

## Navigation Data

- **Enable Navigraph navdata updates**: Adds the Navigation Data tab to the sidebar for downloading and updating AIRAC cycles directly from Navigraph for X-Plane 12 and supported add-ons.

---

## Script Environment

- **Global Environment Variables**: Key-value pairs passed to pre-launch scripts across all profiles.
- **Add / Remove**: Use the `+` and `-` buttons below the table to add or remove variable entries.
- **Profile Overrides**: Variables defined in a profile's **Profile Scripts** tab override global variables with the same key name.

---

## Advanced Settings

- **Global Command-Line Arguments**: Optional command-line arguments passed directly to the X-Plane 12 executable when launching the simulator across all profiles.
  - Useful for debugging or custom automation (e.g. `--fps_test=1`, `--no_sound`, `--verbose`).
  - Collapse or expand this section using the disclosure arrow.


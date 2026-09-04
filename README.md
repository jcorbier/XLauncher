# X-Plane Launcher

A native macOS manager and launcher for X-Plane 12.

X-Plane Launcher lets you organize your add-ons in a central folder, create distinct profiles (e.g. VATSIM, airliner, general aviation), reorder scenery, keep add-ons updated, and launch X-Plane with the exact configuration you need.

## Features

- **Profiles & Profile Manager**: Save and switch configurations across aircraft, plugins, scenery packs, and FlyWithLua scripts. Manage, duplicate, compare, and import/export profiles from a dedicated Profile Manager window.
- **Multiple Storage Folders (Storage Pools)**: Store add-ons across multiple drives or folders (e.g. fast local SSD for aircraft/plugins, large external disk for scenery). If an external drive is unmounted, add-ons remain safely tracked.
- **Clean symlink management**: Keep your X-Plane directory tidy. Add-ons stay in your storage folders and are symlinked into X-Plane on demand.
- **Add-on Categorization & Custom Tagging**: Automatically classify aircraft (Airliners, GA, Military, Helicopters), scenery (Airports, Mesh/Ortho, Landmarks, Libraries), and plugins with smart heuristics. Assign custom tags, override categories, and quickly filter or search your add-on library.
- **Add-on Diagnostics & Health Checks**: Verify scenery library dependencies (OpenSceneryX, MisterX, SAM, HandyObjects, etc.), inspect plugin binary Mach-O architectures for Apple Silicon (`arm64`) vs Intel compatibility, find broken symlinks, and apply one-click fixes.
- **Disk Usage Analyzer & Cache Cleanup**: Analyze disk space distribution across categories and storage pools, detect orphan packages, identify top space hogs, and clear shader and crash caches with a single click.
- **X-Plane Log Analyzer**: Built-in viewer and diagnostic engine for `Log.txt`. Inspect crashes, find missing scenery objects and textures, track down FlyWithLua/SASL errors, profile startup loading times, and browse archived sessions.
- **Scenery pack ordering & grouping**: Reorder `scenery_packs.ini` with drag-and-drop, enable or disable packs without deleting files, and organize scenery into groups.
- **Smart add-on installer & deletion**: Drag and drop `.zip` archives, folders, or `.lua` scripts to install add-ons to any configured storage pool, or delete them directly from the UI with automated profile cleanup and unlinking.
- **Add-on updates**: Check and install updates for add-ons supported by SkunkCrafts Updater or X-Updater directly from the UI.
- **In-app self-updates**: Check for new versions, review release notes, and install updates in-place with automatic restart.
- **Navigation data updates**: Download and update AIRAC cycles directly from Navigraph for X-Plane 12 and supported aircrafts.
- **CSL packages & lights**: Manage CSL model matching packages, apply lighting intensity presets (high/medium/low), or restore original lights.
- **Pre-launch scripts & launch arguments**: Run custom shell scripts with profile-specific environment variables before starting X-Plane, and configure global command-line launch arguments in Settings.

## Requirements

- macOS 15.6 or later
- X-Plane 12

## Installation

### Pre-built binaries

Download the latest `XLauncher.dmg` from the [Releases](https://github.com/jcorbier/x-plane-launcher/releases) page and move `XLauncher.app` to your Applications folder.

### Building from source

Requires Xcode or Swift command-line tools:

```bash
git clone https://github.com/jcorbier/x-plane-launcher.git
cd x-plane-launcher
./package.sh
```

This generates `XLauncher.app` in the project root.

## Setup & Organization

On first launch, a welcome assistant helps you configure your paths:
- **X-Plane 12 folder**: Root folder containing `X-Plane.app`.
- **Primary Data Folder**: Default is `~/Library/Application Support/XPlaneLauncher/`.

You can configure additional storage folders (Storage Pools) at any time in **Settings** (for example on external SSDs or secondary drives).

### Directory layout

Store your add-ons in their respective subdirectories inside any configured storage folder:

```text
~/Library/Application Support/XPlaneLauncher/ (or any storage pool)
├── Aircraft/   <-- Source aircraft
├── Plugins/    <-- Source plugins
├── Scenery/    <-- Source scenery packs
└── LuaScripts/ <-- Source FlyWithLua scripts
```

When applying a profile, the launcher creates symlinks in:
- `<X-Plane 12>/Aircraft`
- `<X-Plane 12>/Resources/plugins`
- `<X-Plane 12>/Custom Scenery`
- `<X-Plane 12>/Resources/plugins/FlyWithLua/Scripts`

## Scripting

You can attach shell scripts to profiles to run before X-Plane launches.

- `XLAUNCHER_PROFILE` is automatically set to the active profile name.
- Global environment variables can be configured in **Settings**.
- Per-profile environment variables can be configured in the **Profile Scripts** tab.

An example script is available in [examples/hoppie.sh](examples/hoppie.sh).

## License

MIT License. See [LICENSE](LICENSE) for details.

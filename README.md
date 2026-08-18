# X-Plane Launcher

A native macOS manager and launcher for X-Plane 12.

X-Plane Launcher lets you organize your add-ons in a central folder, create distinct profiles (e.g. VATSIM, airliner, general aviation), reorder scenery, keep add-ons updated, and launch X-Plane with the exact configuration you need.

## Features

- **Profiles**: Save and switch configurations across aircraft, plugins, scenery packs, and FlyWithLua scripts.
- **Clean symlink management**: Keep your X-Plane directory tidy. Add-ons stay in a central folder and are symlinked into X-Plane on demand.
- **Scenery pack ordering & grouping**: Reorder `scenery_packs.ini` with drag-and-drop, enable or disable packs without deleting files, and organize scenery into groups.
- **Add-on updates**: Check and install updates for add-ons supported by SkunkCrafts Updater or X-Updater directly from the UI.
- **CSL packages & lights**: Manage CSL model matching packages, apply lighting intensity presets (high/medium/low), or restore original lights.
- **Pre-launch scripts**: Run custom shell scripts with profile-specific environment variables before starting X-Plane (e.g. setting up Hoppie ACARS).

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
- **Central Data Folder**: Default is `~/Library/Application Support/XPlaneLauncher/`.

### Directory layout

Store your add-ons in their respective subdirectories inside the central folder:

```text
~/Library/Application Support/XPlaneLauncher/
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

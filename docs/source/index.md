# X-Plane Launcher Documentation

**X-Plane Launcher** (XLauncher) is a native macOS manager and profile-based launcher for **X-Plane 12**.

It organizes add-ons in a central folder and creates symbolic links into your X-Plane installation based on your selected profile. This allows you to switch between configurations—such as online airliner flying, offline bush trips, or testing—without moving large folders or duplicating files.

```{image} https://img.shields.io/badge/platform-macOS%2014.0%2B-blue
:alt: Platform: macOS 14.0+
```
```{image} https://img.shields.io/badge/X--Plane-12-orange
:alt: Simulator: X-Plane 12
```
```{image} https://img.shields.io/badge/license-MIT-green
:alt: License: MIT
```

## Features

::::{grid} 1 2 2 2
:gutter: 3

:::{grid-item-card} Profiles
Save and switch configurations across aircraft, plugins, scenery packs, and FlyWithLua scripts.
:::

:::{grid-item-card} Symlink Management
Keep your X-Plane directory tidy. Add-ons remain in a central directory and are linked into X-Plane on demand.
:::

:::{grid-item-card} Scenery Ordering & Groups
Reorder `scenery_packs.ini` with drag-and-drop, group related scenery entries, and toggle packages without moving files.
:::

:::{grid-item-card} Add-on Installer & Deletion
Install packages with drag-and-drop, and cleanly delete unwanted add-ons with automated profile and symlink cleanup.
:::

:::{grid-item-card} Add-on Updates
Check and install updates for add-ons that use SkunkCrafts Updater or X-Updater directly from the application.
:::

:::{grid-item-card} Navigation Data (Navigraph)
Download and update AIRAC cycles directly from Navigraph for X-Plane and supported aircrafts.
:::

:::{grid-item-card} CSL Packages & Lights
Install and update IVAO/X-CSL model matching packages, and optionally apply native X-Plane 12 lighting presets.
:::

:::{grid-item-card} Pre-Launch Scripts
Run shell scripts before X-Plane starts, passing profile-specific and global environment variables (e.g. for Hoppie ACARS).
:::

::::

## How It Works

X-Plane Launcher manages your add-ons by separating your source files from your simulator installation:

```text
┌─────────────────────────────────────────────────────────────┐
│                    Central Data Folder                      │
│        (~/Library/Application Support/XPlaneLauncher)       │
├──────────────┬──────────────┬───────────────┬───────────────┤
│   Aircraft/  │   Plugins/   │   Scenery/    │  LuaScripts/  │
└──────┬───────┴──────┬───────┴───────┬───────┴───────┬───────┘
       │              │               │               │
       ▼              ▼               ▼               ▼
  [Symlinks]     [Symlinks]      [Symlinks]      [Symlinks]
       │              │               │               │
┌──────┴──────────────┴───────────────┴───────────────┴───────┐
│                    X-Plane 12 Directory                     │
│  • Aircraft/                                                │
│  • Resources/plugins/                                       │
│  • Custom Scenery/ (with scenery_packs.ini)                 │
│  • Resources/plugins/FlyWithLua/Scripts/                    │
└─────────────────────────────────────────────────────────────┘
```

When you select a profile, X-Plane Launcher creates or removes filesystem symbolic links (`symlinks`) inside your X-Plane 12 directory pointing back to your central storage folder. Your original add-on files remain untouched in the central location.

## Contents

```{toctree}
:maxdepth: 2
:caption: Getting Started

getting-started/installation
getting-started/quickstart
```

```{toctree}
:maxdepth: 2
:caption: User Guide

user-guide/profiles
user-guide/aircraft
user-guide/plugins
user-guide/scenery
user-guide/lua-scripts
user-guide/pre-launch-scripts
```

```{toctree}
:maxdepth: 2
:caption: Advanced Features

features/addon-installer
features/updates
features/navdata
features/csl-models
```

```{toctree}
:maxdepth: 2
:caption: Reference

reference/directory-structure
reference/settings
reference/troubleshooting
```

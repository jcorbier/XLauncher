# Storage Pools

Storage Pools allow you to store add-ons across multiple directories or drives instead of keeping everything in a single folder.

This is useful when using secondary drives or high-capacity external SSDs for large scenery libraries and orthophotos while keeping aircraft and plugins on your internal drive.

---

## Overview

A storage pool is a root directory on any internal or external drive structured like the standard central data folder:

```text
/Volumes/FastSSD/XPlaneAddons/   <-- Storage Pool
├── Aircraft/
├── Plugins/
├── Scenery/
└── LuaScripts/
```

Add-ons across all configured storage pools are aggregated into a single view in **Aircraft**, **Plugins**, **Scenery**, and **Lua Scripts**.

---

## Configuring Storage Pools

You can manage storage pools in **Settings** under the **Storage Pools & Multi-Drive Data Folders** section:

- **Add Storage Pool...**: Select any directory on an internal or external volume.
- **Primary Pool**: Designates the default storage location. New add-on folders are created here by default unless specified otherwise.
- **Default Categories**: Assign specific add-on categories (e.g. Scenery only) to a pool. When installing packages of that type, the installer automatically targets this pool.
- **Disk Usage**: View total and available disk capacity for each mounted drive.
- **Edit / Delete**: Rename a pool, update its default categories, or remove it from the launcher. Removing a pool from the launcher does not delete any files from your drive.

---

## Disconnected and Offline Drives

When an external drive is unmounted or disconnected:

- Add-ons located on that drive remain safely tracked in your profiles.
- The UI displays an **Offline** badge on the affected add-ons and lists.
- When launching X-Plane, the launcher safely skips creating symlinks for offline items rather than reporting errors or removing them from your configuration.
- Once the drive is reconnected, add-ons are immediately available again.

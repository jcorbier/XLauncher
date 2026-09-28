# Add-on Updates

X-Plane Launcher includes a built-in updater that scans your storage pools for add-ons supported by **SkunkCrafts Updater** and **X-Updater**, checks for new versions, and applies updates with support for both release and beta channels.

---

## Supported Updaters

- **SkunkCrafts Updater**: Detects `skunkcrafts_updater.cfg` configuration files, and `skunkcrafts_updater_beta.cfg` when beta channels are available.
- **X-Updater**: Detects `settings.ini`, `x-updater.json`, or `.xupdater/` configuration files.

---

## Release and Beta Channels

By default, add-ons are subscribed to their official **Release** channel. You can opt in to **Beta** updates on a per-add-on basis:

### SkunkCrafts Beta Support
- A SkunkCrafts add-on supports a beta channel when a `skunkcrafts_updater_beta.cfg` file exists in the add-on folder alongside `skunkcrafts_updater.cfg`.
- When beta updates are enabled, the launcher uses `skunkcrafts_updater_beta.cfg` to query the beta manifest, verify file checksums, and apply updates.
- If you switch back to the Release channel, `skunkcrafts_updater.cfg` is selected. Running **Verify & Repair Files** restores release files if beta components were previously installed.

### X-Updater Beta Support
- X-Updater products support beta releases through server snapshots (`type: beta`).
- When beta updates are enabled, the launcher requests beta snapshots from the update server and persists `preferred_release_type = beta` and `beta_enabled = true` in the local settings file (`settings.ini` or `x-updater.json`).
- If no beta snapshot is published remotely, the launcher safely falls back to the latest release snapshot.

### Switching Channels
1. Locate the add-on in the **Updates** tab.
2. Click the dropdown arrow on the action button (or right-click the row for the context menu).
3. Toggle **Enable Beta Updates**.
4. The add-on displays a purple **BETA** badge, and the launcher automatically checks for the latest version on the selected channel.

---

## Checking and Installing Updates

Navigate to the **Updates** tab:

```{image} /_static/images/updates-view.png
:alt: Screenshot of the Updates tab with list of updatable add-ons, current/latest version badges, Update All button, and open console drawer
:align: center
```

### Features:
- **Scan**: Automatically scans configured storage pools across `Aircraft`, `Plugins`, `Scenery`, and `LuaScripts`.
- **Check for Updates**: Queries remote manifest servers for version comparisons.
- **Show Changes**: Click **Show Changes...** from the action menu or context menu to inspect release notes and changelogs before updating.
- **Verify & Repair Files**: Validates all installed files against remote CRC32 checksums and file sizes, re-downloading any missing or corrupted files.
- **Update Individual Add-ons**: Click **Update** next to any add-on with an available update.
- **Update All**: Downloads and applies all available updates in sequence.
- **Live Console**: Click the **Console** button in the header bar to view real-time download logs, HTTP responses, file hashing, and extraction progress.


# Add-on & System Diagnostics

X-Plane Launcher includes a unified **Diagnostics** tool accessible from the sidebar (or via **File** → **Diagnostics...** / <kbd>⇧⌘D</kbd>).

The Diagnostics view combines three powerful diagnostic modes into a single tabbed interface:
1. **Add-on Integrity**: Proactive health checks for installed packages before launching X-Plane.
2. **Disk Usage**: In-depth storage analyzer and cache cleanup.
3. **Session Log**: Runtime analyzer and crash inspector for `Log.txt`.

---

## 1. Add-on Integrity & Diagnostics

The Add-on Integrity scanner inspects all installed scenery packs, plugins, aircraft, and storage pools to detect compatibility issues, missing prerequisites, and broken links.

### Scenery Library Dependencies
- **Missing Known Libraries**: Automatically cross-references scenery dependencies against popular community libraries (e.g. OpenSceneryX, MisterX Library, SAM, HandyObjects, CDB-Library, RuScenery, FlyAgi Vegetation, etc.).
- **Scenery Pack Order Warnings**: Flags missing library definitions in `scenery_packs.ini` or libraries that are disabled while dependent scenery packs are enabled.
- **One-Click Quick Fixes**: Provides direct buttons to open the download page of the missing library or disable the offending scenery pack with one click.

### Mach-O Binary Architecture Inspection
On Apple Silicon Macs (M1/M2/M3/M4), plugins compiled exclusively for Intel (`x86_64`) will fail to load in native X-Plane 12 unless Rosetta is used:
- The diagnostics engine inspects `.xpl` dynamic libraries inside each plugin and aircraft folder.
- Flags plugins that lack native Apple Silicon (`arm64`) slices with a critical warning.
- Reports universal binaries (`arm64` + `x86_64`) as verified native.

### Broken Symlinks & Orphan Links
- Scans simulator directories (`Custom Scenery`, `Resources/plugins`, `Aircraft`, `FlyWithLua/Scripts`) for broken symbolic links pointing to nonexistent files or offline storage pools.
- Offers an automated **Delete Link** quick action to restore directory cleanliness.

---

## 2. Disk Usage Analyzer

The Disk Usage tab provides visibility into where your storage is allocated and helps reclaim disk space.

### Storage Breakdown
- **By Category**: Visual and metric breakdown for Aircraft, Scenery Airports, Orthophotos, Mesh, Scenery Libraries, Plugins, Lua Scripts, and Caches.
- **By Storage Location**: Compares disk consumption between your primary X-Plane installation and each configured Storage Pool.

### Top Space Hogs
- Ranks the 25 largest add-ons across your entire library by total disk size and file count.
- Distinguishes between real directories and symlinks (symlinks report 0 bytes to prevent double-counting).

### Orphan Add-on Detection
- Scans storage pools for add-ons that are not referenced in any configured profile.
- Helps identify forgotten or obsolete test packages taking up disk space.

### One-Click Cache Cleanup
Quickly reclaim gigabytes of disk space by clearing simulator-generated temporary files:
- **Clear Shader Cache**: Empties `<X-Plane 12>/Output/caches` to resolve pipeline cache corruption or free space.
- **Clear Crash Reports**: Deletes accumulated `.dmp` and diagnostic dump files from `<X-Plane 12>/Output/crash_reports`.

---

## 3. Session Log Analyzer

Inspects `<X-Plane 12>/Log.txt` as well as archived flight logs from past sessions.

For complete details on log parsing, crash backtraces, missing asset scanning, and startup profiling, see the [X-Plane Log Analyzer](log-analyzer.md) documentation.

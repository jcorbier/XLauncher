# X-Plane Launcher

X-Plane Launcher is a macOS application designed to simplify the management of your X-Plane 12 plugins and configurations. It allows you to create profiles, toggle plugins on/off, and launch X-Plane with a specific setup.

## Features

- **Profile Management**: Create named profiles (e.g., "VATSIM", "Offline", "Default") to quickly switch between different sets of plugins and scenery.
- **Smart Plugin & Scenery Management**: Keep your X-Plane `plugins` and `Custom Scenery` folders clean. The launcher manages content using symlinks, keeping your actual files organized inside subfolders of the Central Data Folder.
- **Script Execution**: Automatically run shell scripts when launching X-Plane (useful for configuring external tools like Hoppie ACARS based on your active profile).
- **One-Click Launch**: Launch X-Plane directly from the app after selecting your profile.

## Requirements

- macOS 15.6 or later
- X-Plane 12

## Installation

### Building from Source

To build the application, ensure you have Xcode installed (or the Swift command line tools).

1. Clone the repository:
   ```bash
   git clone https://github.com/jcorbier/x-plane-launcher.git
   cd x-plane-launcher
   ```

2. Build and package the app:
   ```bash
   ./package.sh
   ```
   This will create `XLauncher.app`. Move this to your Applications folder.

## Setup

### Central Data Folder & Organizing Resources

X-Plane Launcher uses a **Central Data Folder** to store your managed addons. By default, it is located at:
`~/Library/Application Support/XPlaneLauncher/`

Inside this folder, subdirectories are automatically created for your addons:
- `Plugins/` (for managed plugins)
- `Scenery/` (for custom scenery packs)
- `Aircraft/` (for aircraft)
- `LuaScripts/` (for FlyWithLua scripts)

You can customize the location of the Central Data Folder in App Settings.

#### Folder Structure Example

```text
~/Library/Application Support/XPlaneLauncher/
├── Plugins/    <-- Source for plugins
│   ├── BetterPushback
│   └── ...
├── Scenery/    <-- Source for scenery packs
│   ├── KLAX - Los Angeles
│   └── ...
├── Aircraft/   <-- Source for aircraft
└── LuaScripts/ <-- Source for FlyWithLua scripts

X-Plane 12/
├── Custom Scenery/  <-- Managed by Launcher (contains symlinks)
└── Resources/
    └── plugins/     <-- Managed by Launcher (contains symlinks)
```

## Usage

1. **Open XLauncher**.
2. **Configure Settings**: Go to `XLauncher` > `Settings...` (or `Cmd+,`) to open Settings.
   - **Central Data Folder**: Select or view the central data folder location where all your managed plugins, scenery, aircraft, and Lua scripts live.
   - **X-Plane Location**: Select your X-Plane 12 installation folder (the root folder containing `X-Plane.app`).
   - **Script Environment**: Define global environment variables passed to your profile scripts.
3. **Manage Profiles**:
   - Use the **Aircraft**, **Plugins**, **Scenery**, and **Lua Scripts** tabs to toggle content on/off.
   - Use the "Save Current as Profile" button to save your current configuration as a new profile.
   - Select a profile from the dropdown to instantly apply it.
   - Managing a profile will automatically update the `Aircraft`, `plugins`, `Custom Scenery`, and `FlyWithLua/Scripts` folders with symlinks.
4. **Launch**: Click the "Launch X-Plane" button.

### Scripting

You can associate shell scripts and custom environment variables with each profile. These scripts are executed immediately before X-Plane starts.
- `XLAUNCHER_PROFILE` is automatically set to the name of the active profile.
- Environment variables defined globally in **Settings > Script Environment** are passed to scripts.
- **Per-Profile Environment Variables** (configured in the **Scripts** tab for a selected profile) override global variables, allowing custom per-profile configuration values.

**Example Use Case**: Setting custom credentials or ACARS server settings per-profile.

See `examples/hoppie.sh` for a sample script.

### Scenery Management

X-Plane Launcher provides advanced control over your custom scenery:

1.  **Load Order (scenery_packs.ini)**:
    - The scenery list reflects the exact load order defined in `Custom Scenery/scenery_packs.ini`.
    - **Reorder**: Drag and drop items in the list to change their priority. The INI file is updated immediately.

2.  **Toggle**:
    - Toggling a scenery item OFF sets it to `SCENERY_PACK_DISABLED` in the INI file. The symlink remains, keeping the scenery physically present but disabled in X-Plane.

3.  **Scenery Grouping**:
    - Select multiple scenery items.
    - Click the "Create Group" button in the top-right corner to bundle them together.
    - Groups allow you to organize your scenery list and toggle multiple items at once.
    - Drag and drop items into or out of groups as needed.

4.  **New Scenery**:
    - Any new scenery folders manually added to `Custom Scenery` (not yet in the INI) are detected and placed at the top of the list, matching X-Plane's default behavior.

## License

MIT License. See [LICENSE](LICENSE) for details.

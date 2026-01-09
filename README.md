# X-Plane Launcher

X-Plane Launcher is a macOS application designed to simplify the management of your X-Plane 12 plugins and configurations. It allows you to create profiles, toggle plugins on/off, and launch X-Plane with a specific setup.

## Features

- **Profile Management**: Create named profiles (e.g., "VATSIM", "Offline", "Default") to quickly switch between different sets of plugins and scenery.
- **Smart Plugin & Scenery Management**: Keep your X-Plane `plugins` and `Custom Scenery` folders clean. The launcher manages content using symlinks, keeping your actual files in separate "available" source directories.
- **Script Execution**: Automatically run shell scripts when applying a profile (useful for configuring external tools like Hoppie ACARS based on your active profile).
- **One-Click Launch**: Launch X-Plane directly from the app after selecting your profile.

## Requirements

- macOS 14.0 or later
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

### Organizing Resources

For X-Plane Launcher to work, you need to store your plugins and scenery in "source" folders. By default, the app looks for:

- `X-Plane 12/Resources/available plugins` (for plugins)
- `X-Plane 12/Resources/available scenery` (for scenery packs)

You can configure these paths to be anywhere on your system in the App Settings.

#### Default Setup Example

1. Navigate to your X-Plane 12 folder (e.g., `/X-Plane 12/Resources/`).
2. Create `available plugins` and `available scenery` folders.
3. Move your non-default plugins into `available plugins` and your custom scenery packs into `available scenery`.
4. The structure should look like this:
   ```text
   X-Plane 12/
   ├── Custom Scenery/    <-- Managed by Launcher (contains symlinks)
   └── Resources/
       ├── plugins/           <-- Managed by Launcher (contains symlinks)
       ├── available plugins/ <-- Source for plugins
       │   ├── BetterPushback
       │   └── ...
       └── available scenery/ <-- Source for scenery
           ├── KLAX - Los Angeles
           └── ...
   ```

## Usage

1. **Open XLauncher**.
2. **Configure Settings**: Go to `XLauncher` > `Settings...` (or `Cmd+,`) to open the Settings dialog.
   - **X-Plane Location**: Select your X-Plane 12 installation folder (the root folder containing `X-Plane.app`).
   - **Plugins/Scenery Sources**: (Optional) If you don't use the default folder structure, specify the paths to your available plugins and scenery sources here.
   - **Script Environment**: Define global environment variables that will be passed to your profile scripts (e.g., API keys, user credentials).
3. **Manage Profiles**:
   - Use the **Plugins** and **Scenery** tabs to toggle content on/off.
   - Use the "Save Current as Profile" button to save your current configuration as a new profile.
   - Select a profile from the dropdown to instantly apply it.
   - Managing a profile will automatically update the `plugins` and `Custom Scenery` folders with symlinks.
4. **Launch**: Click the "Launch X-Plane" button.

### Scripting

You can associate a shell script with a profile. When the profile is applied, the script is executed.
The environment variable `XLAUNCHER_PROFILE` is set to the name of the active profile.
Any custom variables defined in **Settings > Script Environment** are also injected into the script's environment.

**Example Use Case**: Configuring Hoppie ACARS network based on profile.

See `examples/hoppie.sh` for a sample script.

### Scenery Management

X-Plane Launcher provides advanced control over your custom scenery:

1.  **Load Order (scenery_packs.ini)**:
    - The scenery list reflects the exact load order defined in `Custom Scenery/scenery_packs.ini`.
    - **Reorder**: Drag and drop items in the list to change their priority. The INI file is updated immediately.

2.  **Toggle**:
    - Toggling a scenery item OFF sets it to `SCENERY_PACK_DISABLED` in the INI file. The symlink remains, keeping the scenery physically present but disabled in X-Plane.

3.  **New Scenery**:
    - Any new scenery folders manually added to `Custom Scenery` (not yet in the INI) are detected and placed at the top of the list, matching X-Plane's default behavior.

## License

MIT License. See [LICENSE](LICENSE) for details.

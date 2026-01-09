# X-Plane Launcher

X-Plane Launcher is a macOS application designed to simplify the management of your X-Plane 12 plugins and configurations. It allows you to create profiles, toggle plugins on/off, and launch X-Plane with a specific setup.

## Features

- **Profile Management**: Create named profiles (e.g., "VATSIM", "Offline", "Default") to quickly switch between different sets of plugins.
- **Smart Plugin Toggling**: Keep your X-Plane `plugins` folder clean. The launcher manages plugins using symlinks, keeping your actual plugin files in a separate "available plugins" directory.
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

For X-Plane Launcher to work, you need to slightly reorganize your X-Plane `Resources` directory.

1. Navigate to your X-Plane 12 folder (e.g., `/X-Plane 12/Resources/`).
2. Create a new folder named `available plugins`.
3. Move all your non-default plugins from the existing `plugins` folder into `available plugins`.
   - **Note**: Leave default plugins (like `PluginAdmin`) in the `plugins` folder if you wish, or move them too. The launcher only manages what's in `available plugins`.
4. The structure should look like this:
   ```text
   X-Plane 12/
   └── Resources/
       ├── plugins/           <-- Managed by Launcher (contains symlinks)
       └── available plugins/ <-- Where you keep your actual plugins
           ├── BetterPushback
           ├── xPilot
           └── ...
   ```

## Usage

1. **Open XLauncher**.
2. **Configure Settings**: Go to `XLauncher` > `Settings...` (or `Cmd+,`) to open the Settings dialog.
   - **X-Plane Location**: Select your X-Plane 12 installation folder (the root folder containing `X-Plane.app`).
   - **Script Environment**: Define global environment variables that will be passed to your profile scripts (e.g., API keys, user credentials).
3. **Manage Profiles**:
   - Use the "Save Current as Profile" button to save your current selection of enabled plugins as a new profile.
   - Select a profile from the dropdown to instantly apply it.
   - Managing a profile will automatically update the `plugins` folder with symlinks to the plugins in `available plugins`.
4. **Launch**: Click the "Launch X-Plane" button.

### Scripting

You can associate a shell script with a profile. When the profile is applied, the script is executed.
The environment variable `XLAUNCHER_PROFILE` is set to the name of the active profile.
Any custom variables defined in **Settings > Script Environment** are also injected into the script's environment.

**Example Use Case**: Configuring Hoppie ACARS network based on profile.

See `examples/hoppie.sh` for a sample script.

## License

MIT License. See [LICENSE](LICENSE) for details.

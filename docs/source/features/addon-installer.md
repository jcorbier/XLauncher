# Add-on Package Installer

X-Plane Launcher includes a built-in installer to make adding new aircraft, scenery packs, plugins, and FlyWithLua scripts simple. Instead of manually unzipping archives and sorting folders into the right directories, you can drop add-on packages directly onto the launcher.

---

## Installing an Add-on

You can install add-ons in two ways:

1. **Drag and Drop**: Drag a `.zip` archive, folder, or `.lua` file directly onto the main launcher window.
2. **Menu Bar**: Select **File** → **Install Add-on...** (or press <kbd>⌘I</kbd>) and choose your file from the file picker.

```{image} /_static/images/addon-installer.png
:alt: Add-on installation dialog showing package details, detected category, destination path, and progress
:align: center
```

---

## Automatic Category Detection

When you drop or select a package, the launcher reads its contents and automatically identifies the type of add-on based on its files:

| Category | Detected Files / Signatures | Target Destination |
| :--- | :--- | :--- |
| **Aircraft** | Flight model definitions (`.acf`) | `<Central Data Folder>/Aircraft/<Name>` |
| **Custom Scenery** | Scenery folders containing `Earth nav data/`, `earth.wed.xml`, `apt.dat`, or `library.txt` | `<Central Data Folder>/Scenery/<Name>` |
| **Plugins** | Plugin binaries inside `mac_x64/`, `win_x64/`, `lin_x64/`, `64/`, or standalone `.xpl` files | `<Central Data Folder>/Plugins/<Name>` |
| **FlyWithLua Scripts** | Lua script files (`.lua`) | `<Central Data Folder>/LuaScripts/<Name>` |

---

## Installation Dialog & Options

Before anything is extracted or copied, the launcher opens an installation sheet where you can review the package details:

- **Add-on Category**: Shows the automatically detected category. You can change this using the segmented picker if an unusual package was misidentified.
- **Folder / Package Name**: Pre-filled with the add-on name. You can edit this field to rename the destination folder before installation.
- **Install Destination**: Displays the full folder path where the files will be placed.
- **Enable immediately after installation**: When checked (default), the new add-on is enabled automatically as soon as installation completes.

Click **Install Add-on** to start extraction. The launcher extracts the files, ensures required executable permissions are set on macOS plugin binaries, refreshes your add-on lists, and links the item if immediate enabling was selected.

---

## Handling Archive Layouts

Add-on authors package `.zip` files in various ways. The installer automatically handles common archive layouts:

- **Nested Root Folders**: If an archive contains a single top-level wrapper folder (for example, `MyScenery_v1.2/MyScenery/...`), the installer extracts the inner add-on folder directly into your Central Data Folder rather than creating redundant nested folders.
- **Flat Archives**: If files are stored at the root of the `.zip` without an enclosing folder, the installer creates a clean folder named after the archive.
- **Single Script Files**: Dropping a standalone `.lua` script file copies it directly into your `LuaScripts` directory.

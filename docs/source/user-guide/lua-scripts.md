# FlyWithLua Scripts

X-Plane Launcher lets you enable or disable FlyWithLua scripts and script directories per profile.

---

## Folder Organization

Place scripts and script folders into the `LuaScripts` subfolder of your Central Data Folder:

```text
<Central Data Folder>/LuaScripts/
├── auto_cockpit_view.lua
├── fov_manager.lua
└── 3jFPS_Wizard/                 # Multi-file script folder
    ├── 3jFPS_Wizard.lua
    └── 3jFPS_settings.txt
```

X-Plane Launcher supports both single `.lua` files and script directories.

---

## Managing Scripts

```{image} /_static/images/lua-scripts-view.png
:alt: Screenshot of the Lua Scripts view showing individual .lua scripts and script folders with toggle switches
:align: center
```

- **Enable a script**: Creates a symbolic link in `<X-Plane 12>/Resources/plugins/FlyWithLua/Scripts/`.
- **Disable a script**: Removes the symbolic link from the `Scripts` folder so FlyWithLua does not load it.

```{note}
FlyWithLua must be present in `<X-Plane 12>/Resources/plugins/FlyWithLua` for scripts to be linked.
```

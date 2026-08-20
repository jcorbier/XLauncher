# Plugins

Plugins add features and third-party tools to X-Plane, but having too many enabled simultaneously can lead to performance drops or plugin conflicts. X-Plane Launcher lets you enable plugins per profile.

---

## Folder Organization

Place plugin folders in the `Plugins` subfolder of your Central Data Folder:

```text
<Central Data Folder>/Plugins/
├── BetterPushback/
├── X-Camera/
└── xPilot/
```

```{important}
Keep default X-Plane plugins (such as `PluginAdmin`) in `<X-Plane 12>/Resources/plugins`. Only store third-party and custom add-on plugins in your Central Data Folder.
```

---

## Managing Plugins

```{image} /_static/images/plugins-view.png
:alt: Screenshot of the Plugins tab showing plugin names, toggle switches, and link status indicators
:align: center
```

- **Enable a plugin**: Creates a symbolic link in `<X-Plane 12>/Resources/plugins/<PluginName>`.
- **Disable a plugin**: Removes the symbolic link from `Resources/plugins/`.
- **Settings & Data**: Because symlinks point directly to the central folder, plugins that write configuration files inside their own directories retain their settings.
- **Delete a plugin**: Right-click the plugin row and select **Delete Add-on...** to permanently delete the plugin from your Central Data Folder and purge it from all profiles after confirmation.

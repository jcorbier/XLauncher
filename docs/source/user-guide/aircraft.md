# Aircraft

X-Plane Launcher lets you organize your aircraft in a central directory and link only selected airframes into your simulator.

---

## Folder Organization

Place aircraft folders into the `Aircraft` subfolder of your Central Data Folder:

```text
<Central Data Folder>/Aircraft/
├── ToLiss A321/
├── ToLiss A340-600/
└── Zibo 737-800X/
```

Each subfolder inside `Aircraft` should be a standalone aircraft folder containing the `.acf` file and related assets.

---

## Managing Aircraft

```{image} /_static/images/aircraft-view.png
:alt: Screenshot of the Aircraft view with toggle switches, search, and link status indicators
:align: center
```

In the **Aircraft** tab:
- **Toggle switch**: Enables or disables the aircraft for the current profile.
- **Enabling an aircraft**: Creates a symbolic link from `<X-Plane 12>/Aircraft/<Folder>` pointing to `<Central Data Folder>/Aircraft/<Folder>`.
- **Disabling an aircraft**: Removes the symbolic link from `<X-Plane 12>/Aircraft/`. Your original aircraft files, liveries, and saved states remain safe in the central directory.

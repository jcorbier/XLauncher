# Scenery

X-Plane loads scenery packages based on the order defined in `scenery_packs.ini`. Higher entries take priority over lower entries.

X-Plane Launcher lets you reorder scenery packages, create collapsible groups, and enable or disable packs without moving or deleting files.

---

## Scenery Hierarchy

In X-Plane, scenery is organized by priority from top to bottom:
1. **Custom Airports** (Top of `scenery_packs.ini`)
2. **Landmarks & Regional Scenery**
3. **Libraries** (e.g. OpenSceneryX, MisterX Library)
4. **Overlays & Forests** (e.g. SimHeaven X-World)
5. **Photoreal Orthos & Mesh** (Bottom of `scenery_packs.ini`)

---

## Folder Organization

Place scenery packages in the `Scenery` subfolder of your Central Data Folder:

```text
~/Library/Application Support/XPlaneLauncher/Scenery/
├── Aerosoft - EDDF Frankfurt/
├── FlyTampa - KLAS Las Vegas/
├── OpenSceneryX/
├── simHeaven_X-World_Europe-1-vfr/
├── simHeaven_X-World_Europe-2-regions/
├── simHeaven_X-World_Europe-3-forests/
└── z_ortho_Europe/
```

X-Plane Launcher creates symbolic links in `<X-Plane 12>/Custom Scenery/` and manages the `scenery_packs.ini` file.

---

## Managing Scenery

```{image} /_static/images/scenery-view.png
:alt: Screenshot of the Scenery view showing drag-and-drop handles for reordering, scenery groups, and toggle switches
:align: center
```

### Reordering Scenery
- Drag any scenery row up or down using its drag handle to adjust its load order.
- The order is automatically saved and written to `scenery_packs.ini`.

### Enabling & Disabling
- Toggle the checkbox next to any scenery pack.
- When disabled, X-Plane Launcher marks the entry as `SCENERY_PACK_DISABLED` in `scenery_packs.ini` (or removes the symlink), preventing X-Plane from loading it.

---

## Scenery Groups

If you use multi-folder scenery packages (such as SimHeaven regional sets), you can organize them into groups:

1. Select multiple scenery items (hold `Shift` or `Command` while clicking).
2. Click **Create Group** in the top toolbar.
3. Enter a name for the group.

### Group Actions
- **Expand / Collapse**: Click the chevron to expand or collapse group members.
- **Reorder Group**: Dragging a group moves all member packages together.
- **Ungroup**: Right-click the group header and choose **Ungroup** to restore individual rows.

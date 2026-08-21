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

1. Select one or more scenery items (hold `Shift` or `Command` while clicking).
2. Right-click any selected item and choose **Create Group from Selection...**.
3. Enter a name for the group.

### Group Actions
- **Expand / Collapse**: Click the chevron to expand or collapse group members.
- **Reorder Group**: Dragging a group moves all member packages together.
- **Add Items to Group**: Drag any scenery pack or selection onto a group header to move them into that group.
- **Remove from Group**: Right-click a grouped scenery item and choose **Remove from Group**.
- **Rename Group**: Right-click the group header and choose **Rename...**.
- **Delete Group**: Right-click the group header and choose **Delete Group** to remove the group (individual scenery packages remain intact).

---

## Deleting Scenery

Managed scenery packs (located in your Central Data Folder) can be deleted from the UI:
- Right-click any managed scenery row and choose **Delete Add-on...**.
- Confirming the deletion removes the scenery folder from your Central Data Folder, unlinks it from `Custom Scenery/`, updates `scenery_packs.ini`, and cleans up any scenery groups and profiles.
- Unmanaged scenery residing directly in X-Plane's `Custom Scenery` directory is protected and cannot be deleted by the launcher.

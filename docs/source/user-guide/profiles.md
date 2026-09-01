# Profiles

Profiles let you save and switch between distinct configurations across aircraft, plugins, scenery packs, FlyWithLua scripts, and pre-launch scripts.

---

## Profile Bar

The profile bar appears at the top of all Add-ons views (**Aircraft**, **Plugins**, **Scenery**, **Lua Scripts**, and **Profile Scripts**):

- **Profile Picker**: Selects the active profile. Switching profiles updates symlinks in your X-Plane folder and regenerates `scenery_packs.ini`.
- **Save New (`+`)**: Prompts for a profile name and creates a new profile based on current selections.
- **Update**: Saves changes to the active profile. A highlighted indicator appears when current selections differ from saved state.
- **Manage Profiles (`...` / ⌘P)**: Opens the dedicated Profile Manager window.

---

## Profile Manager Window

Press <kbd>⌘P</kbd> or choose **File** → **Manage Profiles...** to open the Profile Manager.

The manager provides a master list of all saved profiles on the left and a detailed inspector on the right.

### Managing Profiles

From the sidebar:
- **Search**: Filter profiles by name.
- **Sort**: Sort profiles alphabetically (A-Z, Z-A) or by total add-on count (most / least add-ons).
- **Context Menu / Actions**: Right-click any profile to:
  - **Activate**: Switch to this profile immediately.
  - **Duplicate**: Create a copy of the profile.
  - **Rename**: Change the profile name.
  - **Export JSON...**: Save the profile definition to an external `.json` file.
  - **Delete**: Remove the profile.

---

## Profile Inspector & Comparison

Selecting a profile in the Profile Manager displays its configuration in the inspector:

### Overview & Missing Add-on Tracking
- Shows total counts and lists for aircraft, plugins, scenery packs, Lua scripts, and pre-launch scripts.
- **Missing / Offline Indicators**: If a profile references an add-on on a disconnected external storage pool or a folder that was deleted, an alert badge indicates how many items are offline or missing.

### Side-by-Side Comparison (Diff)
You can compare any two profiles to see differences:
1. Select a profile in the sidebar.
2. In the inspector header, use the **Compare with...** dropdown to pick a second profile.
3. The comparison view categorizes items into:
   - **Only in Profile A**
   - **Only in Profile B**
   - **Shared in both profiles**

---

## Import and Export

- **Export**: Right-click a profile in the Profile Manager and choose **Export JSON...** (or click Export in the toolbar) to share or back up your profile setup.
- **Import**: Click **Import Profile...** in the Profile Manager toolbar to load a previously exported JSON profile.

---

## Modified State Tracking

When you toggle an add-on, reorder scenery, or change pre-launch scripts while a profile is active:
- A **Modified** badge indicates unsaved changes.
- Click **Update** to write the changes to disk.
- Switching to another profile without updating discards unsaved toggles and reverts to the saved profile state.

---

## What Profiles Store

Each profile saves:
- **Aircraft**: Selected aircraft folders linked into `<X-Plane 12>/Aircraft`.
- **Plugins**: Selected plugin folders linked into `<X-Plane 12>/Resources/plugins`.
- **Scenery**: Enabled state of custom scenery packs in `scenery_packs.ini`. (Order and group structure are shared across profiles).
- **Lua Scripts**: Selected scripts linked into `<X-Plane 12>/Resources/plugins/FlyWithLua/Scripts`.
- **Profile Scripts**: Shell scripts configured to run before X-Plane starts.
- **Profile Environment Variables**: Custom environment variables passed to pre-launch scripts.

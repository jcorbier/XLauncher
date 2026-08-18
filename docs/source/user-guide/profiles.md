# Profiles

Profiles let you save and switch between distinct configurations across aircraft, plugins, scenery packs, FlyWithLua scripts, and pre-launch scripts.

---

## Overview

```{image} /_static/images/profile-bar.png
:alt: Screenshot of the profile bar showing profile picker, new profile button, save button with modified indicator, and delete button
:align: center
```

The profile bar is displayed at the top of the Add-ons views (**Aircraft**, **Plugins**, **Scenery**, **Lua Scripts**, and **Profile Scripts**):

- **Profile Picker**: Switches the active profile. Selecting a profile immediately updates the symlinks and scenery configuration in your X-Plane folder.
- **Save New (`+`)**: Prompts for a profile name and creates a new profile based on your current selections.
- **Update**: Saves changes to the active profile. An orange dot appears on this button whenever your current configuration differs from what is saved.
- **Delete**: Deletes the selected profile. This removes the profile configuration from the launcher without deleting any files from your Central Data Folder.

---

## Modified State Tracking

When you toggle an add-on, change scenery ordering, or modify pre-launch scripts while a profile is selected:
- A **Modified** indicator highlights that the active profile has unsaved modifications.
- Clicking **Update** updates the saved profile definition on disk.
- Switching to another profile without saving will discard unsaved toggles and load the selected profile's saved state.

---

## What Profiles Store

Each profile saves:
- **Aircraft**: Which aircraft folders are linked into `<X-Plane 12>/Aircraft`.
- **Plugins**: Which plugin folders are linked into `<X-Plane 12>/Resources/plugins`.
- **Scenery**: Which scenery packs are enabled in `scenery_packs.ini`. (The load order and custom groups are shared globally across profiles).
- **Lua Scripts**: Which scripts are linked into `<X-Plane 12>/Resources/plugins/FlyWithLua/Scripts`.
- **Profile Scripts**: The list of shell scripts enabled for execution before launch.
- **Profile Environment Variables**: Environment variables specific to the profile.

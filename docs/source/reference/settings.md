# Settings

This page details the options available in the **Settings** view.

```{image} /_static/images/settings-view.png
:alt: Screenshot of the Settings view with General, X-CSL Models, and Script Environment sections
:align: center
```

---

## General

- **X-Plane Location**: The folder containing your X-Plane 12 installation (where `X-Plane.app` is located). Click the folder button to change the path.
- **Central Data Folder**: The folder where your source add-ons are stored. Defaults to `~/Library/Application Support/XPlaneLauncher/`.
- **Welcome Guide**: Click **Show Welcome Screen...** to reopen the initial setup assistant.

---

## X-CSL Models

- **Enable X-CSL support**: Adds the CSL tab to the sidebar for managing multiplayer aircraft models in `<X-Plane 12>/Resources/plugins/IVAO_CSL/CSL`.
- **Apply modern X-Plane 12 lighting to X-CSL models**: Injects photometric parameterized lighting, ground spill, dynamic strobe sequences, and gear-coupled taxi light animations into installed CSL aircraft models.

---

## Script Environment

- **Global Environment Variables**: Key-value pairs passed to pre-launch scripts across all profiles.
- **Add / Remove**: Use the `+` and `-` buttons below the table to add or remove variable entries.
- **Profile Overrides**: Variables defined in a profile's **Profile Scripts** tab override global variables with the same key name.

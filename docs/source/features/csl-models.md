# CSL Models & XP12 Lighting

When flying on online networks such as VATSIM or IVAO, pilot clients use **CSL (Common Sound and Light) models** for multiplayer aircraft rendering and model matching.

X-Plane Launcher includes an integrated manager for **X-CSL model packages** and an option to apply modern **X-Plane 12 parameterized lighting** to installed CSL models.

---

## Enabling X-CSL Support

1. Open **Settings** from the sidebar.
2. In the **X-CSL Models** section, toggle **Enable X-CSL support** on.
3. The **CSL** category will appear in the sidebar.

---

## Managing CSL Packages

Navigate to the **CSL** tab:

```{image} /_static/images/csl-view.png
:alt: Screenshot of the CSL Models tab showing installed and available aircraft packages, filter picker, check button, and update all button
:align: center
```

- **Browse & Filter**: Filter packages by All, Installed, Updates, or Available.
- **Install & Update**: Download packages directly into `<X-Plane 12>/Resources/plugins/IVAO_CSL/CSL/`.
- **Update All**: Updates all out-of-date packages in one action.

---

## X-Plane 12 Parameterized Lighting

When **Apply modern X-Plane 12 lighting to X-CSL models** is enabled in Settings:
- The launcher modifies installed CSL `.obj` files to use X-Plane 12 photometric parameterized lights (`LIGHT_PARAM`).
- Features include billboard lighting, ground spill, dynamic strobe/beacon sequences, and gear-coupled light animations.
- Original model files are backed up with a `.bak` extension, allowing original lighting to be restored if needed.

This work is based on the [Lights updater for Bluebell and X-CSL packages to XP12 lights](https://forums.x-plane.org/files/file/90389-lights-updater-for-bluebell-and-x-csl-packages-to-xp12-lights/) script.

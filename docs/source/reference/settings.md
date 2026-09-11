# Settings

This page details the options available in the **Settings** view.

---

## X-Plane Installation

- **X-Plane Location**: The folder containing your X-Plane 12 installation (where `X-Plane.app` is located). Click **Browse...** to select your folder. A status indicator confirms whether an X-Plane 12 installation was detected.

---

## Licensing & Edition

Manage your application edition and Pro license activation:

- **Edition Status**: Displays whether XLauncher is running as the **Standard Edition** or **XLauncher Pro Edition**.
- **Upgrade to Pro...**: Opens the in-app purchase dialog to acquire a lifetime license (€5.00) via Stripe.
- **Open License File...**: Activates a purchased license using an exported `.lic` license file or by pasting your license key.
- **Active License Details**: When activated, displays:
  - **License Key**: Masked representation of your active license key.
  - **Activated Machine**: Hardware machine name bound to the license.
  - **License Type**: Node-locked lifetime license (valid on up to 3 Macs).
- **Export License File...**: Exports an `xlauncher.lic` file to transfer your activation to another of your personal Macs.
- **Copy Key**: Copies the full active license key string to the clipboard.
- **Deactivate Machine...**: Releases the activation seat for this machine on the licensing server, reverting this computer to the standard edition so the seat can be used elsewhere.

---

## Storage Pools & Multi-Drive Data Folders

Configure multiple storage locations across internal and external/Thunderbolt drives:

- **Add Storage Pool...**: Add an additional source directory on any mounted volume.
- **Primary**: Set which pool acts as the default destination for new add-ons.
- **Default Categories**: Assign specific add-on categories (Aircraft, Plugins, Scenery, Lua Scripts) to a pool.
- **Drive Metrics**: Displays current mount status, volume name, and available disk capacity.
- **Edit / Delete**: Rename a pool, update its category assignments, or remove the pool reference (files on disk remain intact).

---

## General & Assistance

- **Welcome Guide**: Click **Show Welcome Screen...** to reopen the initial setup assistant and path configuration dialog.

---

## Simulator Launch & Companion Mode

Control application window behavior when launching X-Plane:

### When X-Plane launches
- **Minimize to Menu Bar (Companion Mode)** *(Default)*: Hides the main window and activates the companion item in the macOS menu bar.
- **Keep XLauncher Window Open**: Leaves the main window open alongside the simulator.
- **Quit XLauncher Immediately**: Quits the launcher application as soon as the simulator starts.

### When X-Plane exits (Companion Mode)
- **Reopen XLauncher Window** *(Default)*: Restores the main launcher window when X-Plane closes.
- **Quit XLauncher**: Quits the launcher application when X-Plane closes.

---

## Automatic Updates

Configure which components automatically check for new versions and updates when X-Plane Launcher starts:

- **X-Plane Launcher application**: When enabled, checks GitHub for new application versions on startup.
- **SkunkCrafts add-ons**: When enabled, queries remote servers for updates to SkunkCrafts-managed add-ons on startup.
- **X-Updater add-ons**: When enabled, queries remote servers for updates to X-Updater-managed add-ons on startup.
- **X-CSL models**: When enabled, synchronizes the package index and checks for model updates from the X-CSL repository on startup (available when X-CSL support is enabled).
- **Navigation data (Navigraph)**: When enabled, checks Navigraph for newly published AIRAC cycles on startup (available when Navigation Data support is enabled).

:::{note}
Disabling automatic checks on launch does not prevent manual checks. You can still check for updates at any time from the **Updates**, **CSL**, **Navigation Data**, or **Settings** tabs.
:::

---

## Application Updates

- **Include pre-release and beta versions**: When enabled, checks for pre-release and beta builds on GitHub in addition to stable releases.
- **Check Now**: Manually checks GitHub for application updates immediately.
- **What's New / Update & Relaunch**: View version release notes and changelogs, or update and relaunch the application in-place directly from the UI (with a manual `.dmg` download option available as a fallback).

---

## X-CSL Models

- **Enable X-CSL support**: Adds the CSL tab to the sidebar for managing multiplayer aircraft models in `<X-Plane 12>/Resources/plugins/IVAO_CSL/CSL`.
- **Apply modern X-Plane 12 lighting to X-CSL models**: Injects photometric parameterized lighting, ground spill, dynamic strobe sequences, and gear-coupled taxi light animations into installed CSL aircraft models.

---

## Navigation Data

- **Enable Navigraph navdata updates**: Adds the Navigation Data tab to the sidebar for downloading and updating AIRAC cycles directly from Navigraph for X-Plane 12 and supported add-ons.

---

## Script Environment

- **Global Environment Variables**: Key-value pairs passed to pre-launch scripts across all profiles.
- **Add / Remove**: Use the `+` and `-` buttons below the table to add or remove variable entries.
- **Profile Overrides**: Variables defined in a profile's **Profile Scripts** tab override global variables with the same key name.

---

## Advanced Settings

- **Global Command-Line Arguments**: Optional command-line arguments passed directly to the X-Plane 12 executable when launching the simulator across all profiles.
  - Useful for debugging or custom automation (e.g. `--fps_test=1`, `--no_sound`, `--verbose`).
  - Collapse or expand this section using the disclosure arrow.

---

## X-Plane Network Settings (Pro)

Configures local REST and WebSocket network communication with X-Plane 12:

- **Host**: IP address or hostname running X-Plane 12 (defaults to `127.0.0.1` for local installations).
- **Port**: Port of the X-Plane 12 Web API (defaults to `8086`).
- **Test Connection**: Tests REST API reachability and reports simulator version and Web API status.

---

## SimBrief Configuration (Pro)

- **Username / Pilot ID**: Your SimBrief username or numeric Pilot ID. Used by the **Flight Dispatch** interface to fetch your latest generated Operational Flight Plan (OFP).



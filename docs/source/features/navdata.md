# Navigation Data (Navigraph)

X-Plane Launcher can download and update AIRAC navigation cycles directly from Navigraph for X-Plane 12 and supported add-ons.

```{image} /_static/images/navdata-view.png
:alt: Screenshot of the Navigation Data tab showing Navigraph account status banner, active AIRAC cycle, add-on cycle status, and management action buttons
:align: center
```

---

## Enabling Navigation Data

1. Open **Settings** from the sidebar (or enable it during the initial welcome setup).
2. In the **Navigation Data** section, turn on **Enable Navigraph navdata updates**.
3. The **Navigation Data** tab will appear in the sidebar under **Add-ons**.

---

## Connecting Your Navigraph Account

1. Go to the **Navigation Data** tab and click **Sign In with Navigraph** in the top banner.
2. In the sign-in dialog:
   - Click the link to open **https://navigraph.com/account/otp** in your web browser.
   - Sign in to your Navigraph account to generate a One-Time Password (OTP).
   - Enter your Navigraph email address and the 6-character OTP into X-Plane Launcher.
   - Click **Sign In**.

---

## Managing Navigation Data Add-ons

### Base X-Plane 12 Custom Data
By default, the launcher always manages the native **X-Plane 12 (Base Custom Data)** located in `<X-Plane 12>/Custom Data`.

### Adding Mappings for Supported Aircraft
To add navigation data for supported add-on aircraft:

1. Click **Add Mapping** (`+`) in the navigation data toolbar.
2. In the dialog, choose an add-on from the **Add-on** dropdown list (e.g., *FlightFactor Boeing 777v2*, *Rotate MD-11*).
3. The launcher automatically analyzes your X-Plane installation and suggests the detected target folder (or defaults to the standard add-on path). You can customize the path if your aircraft is installed in a non-standard directory.
4. Click **Add Mapping**.

### Custom Add-on Mappings
For unlisted add-ons or custom formats:
1. Select **Custom Mapping** in the Add-on dropdown.
2. Enter the custom add-on display name, Navigraph format identifier, and destination subpath relative to your X-Plane root directory.

### Context Menu Actions
Right-click any mapped add-on in the list to:
- **Remove Mapping**: Removes the add-on from the launcher list.
- **Show in Finder**: Opens the target data folder directly in macOS Finder.

---

## Installing & Updating Navdata

- **Check Cycles**: Queries Navigraph for the latest published AIRAC cycle.
- **Install**: For add-ons whose data folders have not yet been populated, click **Install** to download and configure the latest cycle.
- **Update**: Click **Update** on any out-of-date add-on row, or click **Update All** in the toolbar to update all configured add-ons in sequence.

---

## Automatic Update Checks

You can choose whether navigation data cycles are checked automatically when the application starts:

1. Open **Settings** > **Automatic Updates**.
2. Toggle **Navigation data (Navigraph)** on or off.

When disabled, X-Plane Launcher uses locally cached catalog data on launch and will only query Navigraph when you click **Check Cycles**.

---

## Backups & Rollback

Before any update is applied, existing navigation data files are safely backed up to `<X-Plane 12>/Custom Data/Backup_Data/`.

To roll back to a previous cycle:
1. Click **Backups** in the Navigation Data toolbar.
2. Browse previous backups sorted by date and add-on provider.
3. Click **Restore** to roll back your installation to that backup.

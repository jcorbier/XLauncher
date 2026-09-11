# XLauncher Pro

XLauncher Pro is an optional upgrade for X-Plane Launcher that adds real-time simulator telemetry, a live moving map, and automated flight dispatch with SimBrief integration.

---

## Capabilities Overview

| Feature | Standard | Pro |
| :--- | :---: | :---: |
| Profile & Symlink Management | ✓ | ✓ |
| Scenery Pack Ordering & Groups | ✓ | ✓ |
| Add-on Diagnostics & Mach-O Checks | ✓ | ✓ |
| Disk Usage Analyzer & Cache Cleaner | ✓ | ✓ |
| X-Plane Log Analyzer | ✓ | ✓ |
| Add-on, Navdata & CSL Updates | ✓ | ✓ |
| Menu Bar Companion & Process Monitor | ✓ | ✓ |
| **SimBrief Flight Dispatch** | — | **✓** |
| **Interactive Airport Diagrams & Weather** | — | **✓** |
| **10Hz Live Moving Map (MapLibre)** | — | **✓** |
| **Real-Time Telemetry HUD** | — | **✓** |
| **Flight Phase Tracking** | — | **✓** |
| **Multi-Mac Activations (up to 3 Macs)** | — | **✓** |

---

## Licensing & Purchase

XLauncher Pro is sold as a lifetime license (€5.00 one-time payment) valid for up to 3 personal Macs.

### In-App Purchase
1. Open **Settings** > **Licensing & Edition** (or click **Upgrade to Pro** from the Pro badge).
2. Click **Purchase License (€5.00 Lifetime)**.
3. Complete checkout in the embedded Stripe sheet.
4. Upon successful payment, your license activates automatically on the current machine.

### Activating an Existing License
If you already purchased Pro and want to activate it on a second or third Mac:
1. Open **Settings** > **Licensing & Edition** and click **Open License File...**.
2. Select your exported `xlauncher.lic` license file, or paste your license key manually.
3. The license verifies locally against your hardware fingerprint.

### Exporting Your License File
From **Settings** > **Licensing & Edition**:
- Click **Export License File...** to save `xlauncher.lic`.
- Or click **Copy Key** to copy the license key string to the clipboard.

### Deactivating a Mac
To transfer an activation to another computer:
1. Open **Settings** > **Licensing & Edition**.
2. Click **Deactivate Machine...** and confirm.
3. The machine seat is released on the licensing server, and the launcher reverts to Standard edition.

---

## Architecture & Simulator Connectivity

XLauncher Pro communicates directly with X-Plane 12 over two local network protocols:

```text
┌────────────────────────┐                    ┌────────────────────────┐
│      XLauncher Pro     │                    │       X-Plane 12       │
│                        │    REST (/api/v3)  │  • Datarefs            │
│  • Flight Dispatch     │ ─────────────────> │  • Commands            │
│  • Airport Diagrams    │                    │  • Flight Init (v3)    │
│  • Moving Map          │    WebSocket (10Hz)│                        │
│  • Telemetry HUD       │ <───────────────── │  • Aircraft Position   │
│  • Flight Phases       │                    │  • Dynamics / G-Forces │
└────────────────────────┘                    └────────────────────────┘
```

- **REST API (`/api/v3`)**: Used for simulator capability checks, dataref queries, and flight initialization (loading aircraft, runway/ramp positions, fuel, and payload).
- **WebSocket (10Hz)**: Receives real-time streaming aircraft position, orientation, velocity, and force datarefs.

Default connection endpoint is `127.0.0.1:8086`. This can be adjusted in **Settings > X-Plane Network Settings**.

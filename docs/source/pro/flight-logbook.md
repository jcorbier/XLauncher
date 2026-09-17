# Automated Flight Logbook & Landing Analytics

XLauncher Pro includes a persistent pilot logbook and touchdown performance analysis engine. Flights are detected and recorded automatically from simulator telemetry without manual start/stop triggers, third-party plugins, or external background apps.

---

## Automated Flight Recording

Flight sessions are tracked by the 11-stage flight phase state machine:

- **Block Out (`outTime`)**: Recorded when the aircraft transitions from `Parked` to `Taxi Out` (parking brake released and ground movement begins).
- **Wheels Off (`offTime`)**: Recorded at liftoff when the main gear leaves the runway surface (transition from `Takeoff Roll` to `Climb`).
- **Wheels Down (`onTime`)**: Recorded at the exact frame of touchdown (transition from `Approach` to `Touchdown`).
- **Block In (`inTime`)**: Recorded when the aircraft reaches its parking stand, sets the parking brake, and shuts down engines (`Taxi In` to `Completed`).

### Logbook Record Data

Each logbook entry persists the following data:

- **Route**: Departure and arrival ICAO codes and resolved airport names.
- **Aircraft**: Aircraft model name and ICAO designator (inferred from `.acf` aircraft files or livery metadata).
- **Identification**: Callsign and flight number (imported from SimBrief OFP or retrieved from X-Plane datarefs).
- **Flight Timeline**: Out, off, on, and in timestamps.
- **Calculated Durations**: Total block time and total airborne flight time.
- **Flight Performance**: Distance flown (great-circle nautical miles), maximum altitude (feet MSL), and maximum groundspeed (knots).
- **SimBrief Metadata**: Linked SimBrief OFP identifier when dispatched via the launcher.
- **Remarks**: User-editable text field for flight notes or ATC remarks.

---

## Precision Landing Analytics

Touchdown dynamics are sampled at the exact instant the main landing gear contacts the runway surface:

- **Vertical Speed**: Sink rate at touchdown measured in feet per minute (FPM).
- **Normal G-Force**: Peak vertical impact load factor in G units.
- **Pitch Angle**: Aircraft pitch attitude in degrees (`+` nose up, `-` nose down).
- **Bank Angle**: Aircraft bank angle in degrees (`+` right wing down, `-` left wing down).
- **Touchdown Groundspeed**: Aircraft forward groundspeed at contact in knots.
- **Touchdown Position**: Exact geographic coordinates (latitude and longitude) and UTC timestamp of the touchdown.

### Landing Quality Ratings

Touchdowns are categorized automatically using vertical speed thresholds:

| Rating | Vertical Speed Threshold | Rating Color |
| :--- | :--- | :--- |
| **Butter Smooth** | `< 100 FPM` | Emerald / Mint |
| **Soft** | `100 – 180 FPM` | Green |
| **Normal** | `180 – 350 FPM` | Sky Blue |
| **Firm** | `350 – 500 FPM` | Amber / Orange |
| **Hard** | `> 500 FPM` | Coral / Red |

### Post-Flight Summary Side Panel

Immediately upon deceleration on the runway, an in-map summary card appears automatically on the moving map. It displays touchdown metrics, the landing rating badge, the flight timeline, and key performance statistics, with a direct button to inspect the record in the full logbook.

---

## Route Breadcrumbs & Map Replay

During airborne flight, the telemetry engine records downsampled GPS coordinates (`latitude`, `longitude`) along the flight trajectory.

From the logbook entry inspector:
- Click **View on Map** to open the interactive moving map.
- The historical route breadcrumb trail is plotted in full with departure and destination airport markers.

---

## Logbook Interface & Management

The logbook interface is accessible under the **Logbook** navigation tab in XLauncher:

### Summary Statistics Strip
A summary stats bar at the top of the window provides career aggregate metrics:
- **Total Flights**: Total completed flight records.
- **Flight Hours**: Cumulative airborne flight time.
- **Block Hours**: Cumulative block time (gate-to-gate).
- **Total Distance**: Total nautical miles flown.
- **Average Landing Rate**: Lifetime average touchdown vertical speed in FPM.
- **Butter Landing Percentage**: Proportion of recorded landings under 100 FPM.

### Search, Filtering & Sorting
- **Search**: Search by departure ICAO, arrival ICAO, airport names, aircraft model, aircraft ICAO, callsign, flight number, or date.
- **Rating Filter**: Filter the list by landing rating (`All`, `Butter Smooth`, `Soft`, `Normal`, `Firm`, `Hard`).
- **Sorting Options**:
  - `Newest First` (default)
  - `Oldest First`
  - `Best Landing (Softest)`
  - `Longest Flight`

### Record Management
- Select any entry from the master list to inspect the detailed flight timeline, landing performance card, performance metrics, and remarks.
- Edit remarks directly in the text editor. Changes save automatically to disk.
- Delete individual entries or clear all entries via the toolbar actions.

---

## Exporting Logbook Data

Logbook data can be exported at any time from the toolbar:

### CSV Export
Click **Export CSV...** to generate a standard comma-separated values file compatible with spreadsheet software and pilot logbook applications:

```text
Date,Flight Number,Callsign,Aircraft ICAO,Aircraft Name,Departure,Arrival,Block Time (s),Flight Time (s),Distance (NM),Max Altitude (ft),Max Speed (kts),Landing Rating,Vertical Speed (FPM),G-Force,Pitch (deg),Bank (deg),Touchdown Speed (kts),Remarks
```

### JSON Export
Click **Export JSON...** to export the entire logbook as a pretty-printed, ISO-8601 formatted JSON array for automated backups or custom scripting.

---

## Local Storage & Privacy

All logbook data and route breadcrumbs are stored strictly on your local disk:

- **Storage Path**: `~/Library/Application Support/XLauncher/PlugInsData/com.jcorbier.XLauncherPro/flight_logbook.json`
- **Privacy**: No telemetry, flight history, callsigns, or landing metrics are uploaded to external servers or cloud services.

# Flight Dispatch & SimBrief Integration

XLauncher Pro includes a flight dispatch interface accessible from the **Map** tab. It combines SimBrief flight plan imports, real-world METAR/TAF weather, vector airport diagrams from `apt.dat`, and direct simulator initialization.

---

## SimBrief OFP Import

XLauncher Pro connects directly to the SimBrief API to retrieve your latest generated Operational Flight Plan (OFP).

### Setup
1. Open **Settings** > **SimBrief Configuration**.
2. Enter your SimBrief **Username** or **Pilot ID**.

### Importing a Flight Plan
In the dispatch panel:
1. Click **Import SimBrief OFP**.
2. XLauncher fetches the latest flight plan and populates:
   - **Route**: Departure, destination, and alternate ICAO codes.
   - **Cruise Altitude**: Planned flight level (e.g., FL360).
   - **Weights**: Planned block fuel, payload, and Zero Fuel Weight (ZFW).
   - **Route Waypoints**: Waypoint list and great-circle route line rendered on the map.
3. **Aircraft Matching**: The dispatch engine reads the SimBrief aircraft ICAO type (e.g. `B738`, `A321`, `A339`) and matches it against your installed X-Plane fleet. If multiple matches exist, select the preferred variant and livery from the dropdown.
4. **OFP Viewer**: Click **View OFP Details** to inspect the full raw text flight plan, including dispatch remarks, routing, wind aloft forecasts, and alternate airport breakdown.

---

## Interactive Airport Diagrams

Airport surface data is extracted directly from X-Plane 12's `apt.dat` files (both default data and custom scenery packs):

- **Surface Geometry**: Renders runway outlines, taxiway networks, helipads, and ramp starts.
- **Search**: Search any global airport by ICAO code, IATA code, or airport name.
- **Runway Selection**: Click a runway threshold to choose your takeoff runway or final approach distance (Threshold, 3 NM, 5 NM, 10 NM).
- **Ramp / Gate Selection**: Filter and click individual parking stands, gates, or ramp spots.
- **Runway Wind Analysis**: Calculates headwind and crosswind components for each runway end using current METAR winds.

---

## Weather & Environmental Presets

### Real-Time Weather (METAR / TAF)
- Decodes METAR and TAF reports for departure, destination, and alternate airports.
- Displays flight category badges:
  - **VFR** (Green): Ceiling > 3,000 ft and Visibility > 5 SM.
  - **MVFR** (Blue): Ceiling 1,000–3,000 ft or Visibility 3–5 SM.
  - **IFR** (Red): Ceiling 500–1,000 ft or Visibility 1–3 SM.
  - **LIFR** (Magenta): Ceiling < 500 ft or Visibility < 1 SM.
- Displays altimeter setting, temperature, dew point, wind speed, and gust limits.

### Date & Time Configuration
Choose the simulator starting time:
- **Live UTC**: Synchronizes to current real-world UTC time.
- **Local Noon**: Sets the simulator sun position to local solar noon at the departure airport.
- **Sunrise / Sunset**: Computes sun position for dawn or dusk departures.
- **Night**: Sets midnight local time.
- **Manual**: Specify exact date and local time.

### Weather Configuration
- **Real-world Weather**: Configures X-Plane 12 to download and inject live NOAA global weather.
- **Manual / Preset**: Allows configuring custom cloud layers and visibility.

---

## Simulator Flight Initialization

Once dispatch configuration is complete:

1. Select **Engines State**:
   - **Cold & Dark**: Aircraft spawns with engines shut down, systems unpowered.
   - **Engines Running**: Aircraft spawns configured for immediate departure.
2. Click **Initialize Flight**:
   - If X-Plane 12 is already running, XLauncher sends the flight initialization payload via the Web API (`/api/v3/init/flight`). The simulator reloads the scenario immediately at the selected gate or runway with the requested fuel, payload, weather, and time.
   - If X-Plane 12 is not running, XLauncher applies your active profile symlinks and launches the simulator with the pre-configured parameters.

# X-Plane Log Analyzer

The built-in X-Plane Log Analyzer parses `Log.txt` to diagnose crashes, pinpoint missing scenery dependencies, troubleshoot Lua/SASL errors, and profile loading performance.

---

## Opening the Log Analyzer

You can open the analyzer in two ways:
- Click **X-Plane Logs** under the **System** section in the main sidebar.
- Choose **File** → **X-Plane Logs...** (or press <kbd>⇧⌘L</kbd>) to open it in a standalone window.

---

## Log Sources and Session Archives

The toolbar at the top of the window provides access to current and historical logs:

- **Current Log**: Automatically loads `<X-Plane 12>/Log.txt`.
- **Session Archives**: The launcher archives past logs before each simulator run, allowing you to review logs from previous flights.
- **Open Custom File...**: Load and analyze any external `Log.txt` file from your disk.
- **Refresh**: Reloads the log file from disk if X-Plane is currently running or just closed.

---

## Diagnostic Sections

The analyzer categorizes log data across seven dedicated tabs:

### 1. Overview
Provides an immediate summary of the flight session:
- **System Specifications**: OS version, CPU model and core count, physical RAM.
- **Graphics Backend**: Active Metal GPU device, driver info, and detected VRAM.
- **Simulator Version**: Full X-Plane 12 version string and build number.
- **Session Health**: Summary badges for crash status, total error count, warnings, and missing assets.

### 2. Crash Diagnostics
When X-Plane crashes or exits abnormally, this tab isolates the failure reason:
- **Crash Category**: Identifies whether the crash was caused by a plugin fault, memory exhaustion (RAM/VRAM), a fatal OS signal (e.g. `EXC_BAD_ACCESS`), or an internal simulator assertion.
- **Offending Component**: Identifies the responsible plugin binary or module where available.
- **Backtrace**: Shows the captured stack trace and the exact line number in `Log.txt`.

### 3. Errors & Warnings
Displays logged warnings, errors, and fatal messages:
- **Subsystem Filters**: Filter by category, including Plugins, Scenery, SASL / Avionics, Graphics / Metal, System / Sim, Flight Model, ATC, Weather, and Network.
- **Search**: Search message text or log tags in real time.

### 4. Missing Scenery
Scans scenery loading output to report missing assets:
- **Asset Types**: Identifies missing 3D objects (`.obj`), terrain meshes (`.dsf`), polygons (`.pol`), facades (`.fac`), forests (`.for`), and textures.
- **Referenced By**: Shows which custom scenery pack requested the missing file and suggests common third-party libraries (such as MisterX6, OpenSceneryX, or SAM) when relevant.

### 5. Lua & SASL Errors
Lists runtime script exceptions from:
- **FlyWithLua**: Syntax errors, runtime failures, and missing script dependencies.
- **SASL Avionics**: Aircraft system script errors and stack traces.

### 6. Startup Times
Profiles loading performance during simulator initialization:
- Lists plugin initialization times and identifies slow plugins.
- Lists scenery DSF load durations to help identify heavy scenery tiles.

### 7. Raw Log
Displays the complete, unparsed `Log.txt` file with line numbers, search, and text selection.

---

## Exporting Reports

- **Copy Report**: Copies a formatted Markdown diagnostic summary to your clipboard, ready to paste into support forums or bug reports.
- **Export Report...**: Saves the full diagnostic breakdown to a `.txt` or `.md` file on disk.

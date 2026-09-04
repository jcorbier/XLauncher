# Add-on Categorization & Tagging

X-Plane Launcher includes an intelligent categorization engine and custom tagging system across Aircraft, Scenery, and Plugins.

---

## 1. Automatic Heuristic Categorization

When add-ons are scanned from your storage pools, the launcher automatically infers their category based on names, folder structures, and simulator files:

### Aircraft Categories
- **Airliner**: Boeing, Airbus, Embraer, Bombardier, CRJ, McDonnell Douglas, ATR, etc.
- **General Aviation**: Cessna, Piper, Beechcraft, Cirrus, Diamond, Mooney, Robin, etc.
- **Helicopter**: Bell, Robinson, Eurocopter/Airbus Helicopters, Sikorsky, or `.acf` files declaring `acf/_is_helo 1`.
- **Military**: Fighter aircraft (F-15, F-16, F/A-18, Typhoon, Rafale, Su-27, etc.) and military transports (C-130).

### Scenery Categories
- **Airports**: Packages containing `Earth nav data/apt.dat`, 4-letter ICAO codes (e.g. `LFPG`, `KLAX`, `EGLL`), or airport keywords.
- **Mesh & Ortho**: Orthophoto tiles (`zOrtho4XP`), global overlay meshes (`simheaven_xworld`), and terrain elevation packages.
- **Libraries**: Shared asset libraries containing `library.txt` (OpenSceneryX, MisterX, SAM, HandyObjects, etc.).
- **Landmarks**: City sceneries, VFR objects, bridges, and monuments.

### Plugin Categories
- **Utilities**: General tools, flight planning, terrain radars, and ground handling.
- **Traffic**: Online clients and AI traffic engines (VATSIM/xPilot, LiveTraffic, Traffic Global, X-Life).
- **Weather**: Weather injection engines (Active Sky XP, NOAA Weather, Enhanced Skyscapes).
- **Sound**: Sound enhancements and sound packs (FMOD engines, BSS).

---

## 2. Custom Tags & Category Overrides

You can customize the classification of any add-on without altering any files on disk.

### Editing Tags & Category
1. In the **Aircraft**, **Plugins**, or **Scenery** list view, click the **Tag** icon on any row, or right-click and choose **Edit Category & Tags...**.
2. **Category Override**: Select any category from the picker, or select **Auto-detected** to revert back to heuristic categorization.
3. **Custom Tags**:
   - Type a tag name and press <kbd>Return</kbd> (or click **Add**).
   - Click any suggested tag pill (e.g., `Favorite`, `XP12`, `VFR`, `IFR`, `Payware`, `Freeware`) to quickly attach it.
   - Click the **×** button on any tag chip to remove it.
4. Click **Done**. Your tags and category choices are saved instantly in application preferences.

---

## 3. Search & Multi-Criteria Filtering

Every add-on view features a persistent filter bar at the top:
- **Search Field**: Live search matching add-on names, folder names, category names, or assigned tags.
- **Category Filter**: Dropdown to view only a specific category (e.g. show only *Helicopters* or only *Airports*).
- **Tag Filter**: Dropdown populated dynamically with all tags currently used in that category.
- **Reset Button**: Appears when any filter is active to restore the full list with one click.

```{note}
When a filter or search query is active in the **Scenery** view, drag-and-drop reordering is temporarily disabled to prevent accidental disruption of your `scenery_packs.ini` load order.
```

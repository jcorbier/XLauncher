# Live Moving Map & Telemetry HUD

XLauncher Pro includes a real-time moving map and telemetry monitor that runs alongside X-Plane 12.

---

## Live Moving Map

Accessible under the **Map** tab in the sidebar:

- **Vector, Satellite & Hybrid Layers**: Switch between vector maps, satellite photography, or hybrid views using the style control in the upper-right corner.
- **Aircraft Tracking & Follow Mode**: The active aircraft is shown with its real-time position, true heading, and ground track. Enable **Follow Aircraft** to keep the camera locked onto the aircraft.
- **Flight Trail**: Records an altitude-colored breadcrumb trail of your flight path from departure to destination.
- **Airport Overlays**: Airport layouts (runways, taxiways, and ramp stands) are displayed dynamically as the camera approaches an airport.
- **Camera Controls**: Adjust zoom, bearing, and 3D tilt, or click the compass indicator to reset the view to top-down North-up.

---

## Real-Time Telemetry HUD

Telemetry is streamed from X-Plane 12 at 10Hz over a local WebSocket connection:

### Airspeed & Altitude
- **Indicated Airspeed (KIAS)**, **True Airspeed (KTAS)**, and **Ground Speed (GS)**.
- **Mach Number** readout at high cruise speeds.
- **Barometric Altitude (MSL)** and **Radio / Radar Altitude (AGL)**.

### Dynamics & Attitude
- **Vertical Speed (VS)** in feet per minute.
- **Pitch & Bank**: Pitch ladder and bank angle readouts.
- **True & Magnetic Heading**.
- **G-Meter**: Instantaneous normal G-force acceleration.

### Flight Controls & Configuration
- **Engine Throttle**: Thrust lever percentage.
- **Flap Position**: Current flap setting and deployment progress.
- **Speedbrakes / Spoilers**: Arm and deployment status.
- **Landing Gear**: Individual gear transit and lock status (left, right, nose).

---

## 11-Stage Flight Phase Engine

The telemetry engine runs an automated 11-stage flight phase state machine without requiring manual state toggling:

```text
Parked ──> Taxi Out ──> Takeoff Roll ──> Climb ──> Cruise ──> Descent
                                                                 │
Completed <── Taxi In <── Rollout <── Touchdown <── Approach <───┘
```

1. **Parked**: On ground, zero ground speed, parking brake set.
2. **Taxi Out**: Moving on ground prior to takeoff.
3. **Takeoff Roll**: Ground roll with acceleration above 40 knots.
4. **Climb**: Airborne, positive vertical speed, increasing altitude.
5. **Cruise**: Level flight within cruise altitude margin.
6. **Descent**: Sustained negative vertical speed toward destination.
7. **Approach**: Low-altitude configured descent (flaps/gear extended).
8. **Touchdown**: Moment of wheel contact with the runway surface.
9. **Rollout**: Deceleration on runway surface below flight speed.
10. **Taxi In**: Taxiing toward parking or gate after clearing runway.
11. **Completed**: Parking brake set at destination stand with engines stopped.


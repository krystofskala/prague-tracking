# Architecture

## Layers

```
Packages/StreetTrackerCore/   Pure Swift, no Apple frameworks. Testable
                               anywhere. Owns the domain logic.
  StreetGraph.swift              Segment + graph model
  OSMLoader.swift                Parses raw Overpass API JSON -> StreetGraph
  SpatialGridIndex.swift         Grid bucketing for fast nearest-segment lookup
  MapMatcher.swift               Snaps a GPS fix to the nearest segment
  CoverageStore.swift            Turns matched fixes into passes, pass counts
  CoverageSummary.swift          Coverage % kept up to date incrementally
  PowerPolicy.swift              Precise / saving mode: when fixes may be thinned out
  WalkingSpeedDetector.swift     Walking noticed from GPS speed when Core Motion lags
  RouteSuggester.swift           Nearest-unwalked-street suggestions
  RingAssembler.swift            Stitches boundary way fragments into closed rings
  DistrictTagger.swift           Point-in-polygon tags segments with a cadastral district

App/                           SwiftUI + MapKit + CoreLocation. Thin glue
                               over StreetTrackerCore; no domain logic here.
  Location/LocationTracker.swift        liveUpdates + background session (iOS 17), relaunch
  Location/WalkingActivityMonitor.swift Core Motion filter (skip car/bike fixes)
  Persistence/CoveragePersistence.swift   Local JSON file, on-device only
  ViewModels/TrackingViewModel.swift      Wires location -> matcher -> coverage -> disk
  Views/MapView.swift                     MKMapView bridge, renders polylines by pass count
  Views/ContentView.swift                 Main screen
  Views/SuggestionsView.swift             Nearest-unwalked-streets sheet
```

The split matters because `StreetTrackerCore` can be unit tested in
isolation (map matching correctness, coverage math, route suggestion
ordering) without needing a simulator or device — those are the parts most
likely to have subtle bugs, and the parts that are cheapest to get
confidence in via tests.

## Map matching

Raw GPS is noisy (typically 5-15m error, worse near tall buildings — which
much of central Prague has). You can't just draw a line through raw fixes;
you need to snap each fix onto the street it's actually on. The current
implementation (`MapMatcher`) does **nearest-segment matching**: for each
fix, find nearby segments via a spatial grid index, compute point-to-segment
distance for each, and pick the closest one within a threshold (25m
default).

This is a simplification of the "real" solution, which is a Hidden Markov
Model matcher that also considers transition probability between
consecutive fixes (i.e. penalizes jumping between unrelated streets, favors
paths that are actually connected in the graph — see OSRM's or Valhalla's
map-matching services for reference implementations). Nearest-segment
matching will occasionally mis-snap on tight parallel streets or at complex
intersections. Worth upgrading if that proves to matter in practice; not
worth the complexity for a first version.

The spatial grid indexes every cell an edge passes through, not just the
cells holding its vertices: OSM leaves no nodes along straight stretches
(~1,100 Prague streets have an edge over 150 m, the longest 738 m).
`BundledDataTests` checks the indexed matcher against a brute-force scan
of the real graph.

## Passes

A GPS fix arrives every ~10 m, so a fix is not a pass. `CoverageStore.
recordFix` confirms a segment once it gets a second fix within 60 s (not
necessarily consecutive, so GPS noise flipping between a sidewalk and the
road a few metres away confirms both, while a single snap to a cross street
at an intersection doesn't). Segments under 20 m count on their first fix.
A confirmed segment counts as a new pass only after 10 minutes away from
it, so walking down a street and straight back is one pass. Fixes during a
ride are dropped before the store, so the last walking fix is too old to
confirm anything after you get off.

## Street segments = whole OSM ways

Each segment in the graph is one OSM `way`, not split at intersections. A
very long street (e.g. several hundred meters) counts as "walked" the
moment you cover any part of it. This is simpler and enough to drive the
thickening-line visualization, but coarser than "have I walked every block."

v2 improvement: split ways into edges between consecutive intersection
nodes (nodes shared by 2+ ways), so coverage is block-by-block. This is a
graph preprocessing step in `OSMLoader`, not a change to `MapMatcher` or
`CoverageStore`.

## Coverage & districts

Coverage is computed as **length-weighted fraction walked**, not
segment-count fraction — a 300m street contributes more to "% walked" than
a 30m alley.

District coverage requires each `StreetSegment.district` to be populated.
`OSMLoader` itself always leaves it `nil` (Overpass doesn't tag ways with
cadastral district directly); `TrackingViewModel.loadBundledGraph()` fills
it in as a second pass by loading `App/Resources/prague_districts.json`
(fetched via `Scripts/fetch_prague_districts.sh`) and running
`DistrictTagger.tag`. That pulls Prague's cadastral areas as OSM
`boundary=cadastral` relations (112 katastrální území), reassembles their
member ways into closed rings with `RingAssembler` (boundaries are usually
split across several way fragments in mixed order/direction), and does a
ray-casting point-in-polygon test using each segment's midpoint as its
representative location. If `prague_districts.json` isn't present, the app
still works — every segment's `district` just stays `nil` and coverage
reports as "Unknown".

Known gap: `RingAssembler` only looks at `role: "outer"` members and drops
any way fragment it can't close into a ring, rather than reporting the
failure. For Prague's cadastral relations (simple polygons, not the
multi-ring/enclave shapes some country-level boundaries have) this should
be fine; if a specific district silently doesn't get tagged, this is the
first place to check.

## Route suggestion

`RouteSuggester.nearestUnwalked` returns the nearest *unwalked segments* to
a location, not a turn-by-turn route — surfaced in the app via the "Suggest
nearby streets" button (`SuggestionsView`), using the most recent GPS fix as
the origin. Actually generating an efficient
covering route is the **route inspection / "Chinese Postman" problem**:
find the shortest walk that traverses every unwalked edge. Solving that
well needs:

- An actual routing graph (adjacency between segments, not just a flat list).
- A near-optimal Eulerian-path-style solver, or a simpler greedy
  nearest-unwalked-edge heuristic chained into a loop.

That's meaningfully more scope than the rest of this app and is the
natural "v2" — for now, the nearest-unwalked list plus per-district
coverage is enough to plan a walk by hand.

## Persistence

Pass counts are stored as a flat `[segmentID: Int]` dictionary, serialized
to JSON in Application Support. Fine for an MVP; if the full Prague graph
(tens of thousands of segments) makes JSON re-serialization on every step
noticeably slow, swap `CoveragePersistence` for SQLite (e.g. GRDB) — it's
the only file that touches disk, so this is a contained change.

## Startup and battery

The street graph (~13 MB JSON, 32k segments), district tagging and the
spatial index are built in a detached task at launch; the map shows a
loading indicator meanwhile. On Linux CI (debug build) this takes ~2.5 s.

Tracking runs on iOS 17's `CLLocationUpdate.liveUpdates(.fitness)` while
holding a `CLBackgroundActivitySession`, so iOS relaunches the app in the
background if it ends it mid-walk (significant location changes are a
second way back in). `AppDelegate` owns `TrackingViewModel`, because no
SwiftUI view exists on a background relaunch. iOS pauses GPS by itself
while you stand still.

GPS always runs at full accuracy. Every fix goes to the daily CSV with its
accuracy; only fixes under 50 m snap to streets and draw the orange route.
In **saving** mode (`PowerPolicy`, chosen in the app; **precise** is the
default) fixes are thinned to one per 30 s while Core Motion reports a
vehicle or 2+ minutes of standing still. A steady walking pace from GPS
(`WalkingSpeedDetector`, 30 s) ends saving mode and counts as walking even
before Core Motion catches up after a ride. Mode switches, relaunches and
location errors go to `trasy/udalosti-YYYY-MM-DD.csv`.

## Things to sanity-check on a real device

- **Background behavior**: `allowsBackgroundLocationUpdates` + the
  `location` background mode should keep updates flowing with the screen
  off, but iOS will still throttle/kill apps that don't behave — watch for
  gaps in tracked streets after long backgrounded stretches and tune
  `distanceFilter` / consider `CLLocationManager`'s deferred updates if
  battery drain is too aggressive.
- **Activity filtering**: `WalkingActivityMonitor` skips recording a fix
  while Core Motion confidently reports automotive/cycling activity.
  Low-confidence and unavailable readings fall through to "keep tracking" -
  test that this isn't too permissive (e.g. a slow-moving car in traffic
  might read as ambiguous) or too aggressive (rejecting real walking near
  a road) on an actual device; simulator activity data is unreliable.
- **App Store review**: apps requesting "Always" location access need to
  justify it clearly in the review notes and in the usage-description
  strings (already drafted in `project.yml`) — background fitness tracking
  is a well-understood use case but reviewers still check.

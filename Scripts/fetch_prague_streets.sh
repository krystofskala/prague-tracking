#!/usr/bin/env bash
#
# Fetches Prague's walkable street network from OpenStreetMap via the
# Overpass API and saves it as JSON in the format App/Resources/prague_streets.json
# expects (consumed directly by OSMLoader — no conversion step needed).
#
# Usage:
#   ./Scripts/fetch_prague_streets.sh [output-path]
#
# Run this from a machine with normal internet access (not required inside
# Xcode or the app itself — this is a one-time/occasional data refresh step).

set -euo pipefail

OUT="${1:-App/Resources/prague_streets.json}"

# Which ways count as "streets" (Kryštof's choice, 2026-10-14, option B):
# every NAMED way that is a street (residential ... primary, pedestrian and
# living streets) or a named footway / path / steps / track (Nerudovy schody,
# Petřín paths, ...). Unnamed sidewalks, driveways and forest paths are left
# out: Prague has ~170k highway ways, mostly those, and counting them would
# make 100 % unreachable.
QUERY='[out:json][timeout:180];
area["name"="Praha"]["admin_level"="6"]->.praha;
(
  way["highway"~"^(residential|living_street|pedestrian|unclassified|tertiary|secondary|primary|tertiary_link|secondary_link|primary_link|footway|path|steps|track)$"]["name"](area.praha);
);
out body;
>;
out skel qt;'

echo "Querying Overpass API for Prague's street network (this can take a couple of minutes)..."
curl -sS --fail --retry 5 --retry-delay 30 --retry-all-errors -A "prague-street-tracker/0.1 (+https://github.com/krystofskala/prague-tracking)" --data-urlencode "data=${QUERY}" "${OVERPASS_URL:-https://overpass-api.de/api/interpreter}" -o "$OUT.raw"

# Keep only what OSMLoader reads (way id/nodes/name, node id/lat/lon) so the
# bundled file stays small; the format is still plain Overpass JSON.
python3 - "$OUT.raw" "$OUT" <<'PY'
import json, sys
src, dst = sys.argv[1], sys.argv[2]
elements = json.load(open(src))["elements"]
slim = []
for e in elements:
    if e["type"] == "node":
        slim.append({"type": "node", "id": e["id"], "lat": round(e["lat"], 6), "lon": round(e["lon"], 6)})
    elif e["type"] == "way":
        slim.append({"type": "way", "id": e["id"], "nodes": e["nodes"], "tags": {"name": e["tags"]["name"]}})
ways = sum(e["type"] == "way" for e in slim)
if ways == 0:
    sys.exit("Overpass returned no ways - server problem? Try OVERPASS_URL=<another mirror>")
with open(dst, "w") as f:
    json.dump({"elements": slim}, f, ensure_ascii=False, separators=(",", ":"))
print(f"{ways} ways, {len(slim) - ways} nodes")
PY
rm "$OUT.raw"

echo "Saved to $OUT ($(du -h "$OUT" | cut -f1))"

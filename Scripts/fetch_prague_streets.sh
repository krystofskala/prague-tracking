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

# Excludes motorways/trunk roads (not relevant to walking) and non-physical
# ways (construction, proposed, razed, abandoned). Keeps everything else
# tagged `highway=*` inside Prague's administrative boundary, including
# pedestrian streets, footways, and residential streets.
QUERY='[out:json][timeout:180];
area["name"="Praha"]["admin_level"="6"]->.praha;
(
  way["highway"]["highway"!~"^(motorway|motorway_link|trunk|trunk_link|construction|proposed|razed|abandoned)$"](area.praha);
);
out body;
>;
out skel qt;'

echo "Querying Overpass API for Prague's street network (this can take a couple of minutes)..."
curl -sS --fail --retry 5 --retry-delay 30 --retry-all-errors -A "prague-street-tracker/0.1 (+https://github.com/krystofskala/prague-tracking)" --data-urlencode "data=${QUERY}" "${OVERPASS_URL:-https://overpass-api.de/api/interpreter}" -o "$OUT"

echo "Saved to $OUT ($(du -h "$OUT" | cut -f1))"
echo
echo "This pulls ALL of Prague's non-motorway streets — tens of thousands of ways,"
echo "likely tens of megabytes. Two things worth doing before shipping:"
echo "  1. Tag each segment with its cadastral district (not done by this query -"
echo "     see docs/ARCHITECTURE.md for the district-coverage approach)."
echo "  2. If load time / memory becomes an issue on-device, trim to a bounding"
echo "     box or a handful of districts first and expand later."

#!/usr/bin/env bash
#
# Fetches Prague's cadastral areas (katastrální území - the "districts" used
# for per-area coverage, e.g. Malá Strana, Vinohrady) as OSM administrative
# boundary relations and saves them in the Overpass JSON format
# DistrictTagger expects (App/Resources/prague_districts.json).
#
# Run alongside fetch_prague_streets.sh - both are needed for per-district
# coverage; without this file the app still works, it just leaves every
# segment's district as "Unknown".
#
# Usage:
#   ./Scripts/fetch_prague_districts.sh [output-path]

set -euo pipefail

OUT="${1:-App/Resources/prague_districts.json}"

# In OSM, Czech katastrální území are boundary=cadastral relations (112 in Prague);
# admin_level=9 would give the 57 městské části (Praha 1, Praha-Suchdol, ...) instead.
# `out geom;` embeds each member way's coordinates directly in the relation,
# which is what lets DistrictTagger avoid a separate node-resolution pass.
QUERY='[out:json][timeout:180];
area["name"="Praha"]["admin_level"="6"]->.praha;
relation["boundary"="cadastral"](area.praha);
out geom;'

echo "Querying Overpass API for Prague's cadastral area boundaries..."
curl -sS --fail --retry 5 --retry-delay 30 --retry-all-errors -A "prague-street-tracker/0.1 (+https://github.com/krystofskala/prague-tracking)" --data-urlencode "data=${QUERY}" "${OVERPASS_URL:-https://overpass-api.de/api/interpreter}" -o "$OUT"

echo "Saved to $OUT ($(du -h "$OUT" | cut -f1))"
echo "Re-run fetch_prague_streets.sh too if you haven't, then rebuild the app."

"""Zdroj pro SideStore/AltStore (source.json) s nejnovější verzí appky.
SideStore ho sleduje a novou verzi nabídne v Updates. Volá iOS workflow po
vydání buildu (stejně jako Opentify).

  python altstore_source.py <verze> <url ipa> <velikost> <cesta k source.json> [commit]
"""

import datetime
import json
import os
import sys

version, url, size, out = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]
commit = sys.argv[5] if len(sys.argv) > 5 else ""
repo = os.environ.get("GITHUB_REPOSITORY", "krystofskala/prague-tracking")
raw = f"https://raw.githubusercontent.com/{repo}"

source = {
    "name": "Prague Streets",
    "identifier": "com.krystofskala.praguestreettracker.source",
    "sourceURL": f"{raw}/altstore/source.json",
    "website": f"https://github.com/{repo}",
    "apps": [
        {
            "name": "Prague Streets",
            "bundleIdentifier": "com.krystofskala.praguestreettracker",
            "developerName": "Kryštof",
            "subtitle": "Projdi všechny ulice Prahy",
            "localizedDescription": "Sleduje chůzi, kreslí prošlé pražské ulice a ukazuje pokrytí po čtvrtích. Poloha nikdy neopustí telefon.",
            "iconURL": f"{raw}/main/docs/icon.png",
            "tintColor": "2563EB",
            "versions": [
                {
                    "version": version,
                    # CFBundleVersion appky (= číslo běhu CI).
                    "buildVersion": version.rsplit(".", 1)[-1],
                    # Bez toho SideStore pod verzí ukazuje "nil".
                    "localizedDescription": f"Prague Streets {version}.",
                    "date": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
                    "size": size,
                    "downloadURL": url,
                    "minOSVersion": "16.0",
                }
            ],
            "appPermissions": {
                "entitlements": [],
                "privacy": {
                    "NSLocationWhenInUseUsageDescription": "Zaznamenává, kterými ulicemi jsi prošel. Poloha zůstává jen v telefonu.",
                    "NSLocationAlwaysAndWhenInUseUsageDescription": "Sleduje chůzi i se zamčeným telefonem. Poloha zůstává jen v telefonu.",
                    "NSMotionUsageDescription": "Rozliší chůzi od jízdy autem nebo na kole.",
                },
            },
        }
    ],
    "news": [],
    "appCommit": commit,
}

with open(out, "w", encoding="utf-8") as f:
    json.dump(source, f, ensure_ascii=False, indent=2)
print(f"source.json: {version} -> {url}")

#!/usr/bin/env python3
"""
Fetch up to 1000 airports from OurAirports (public domain) and write
NaarsCars FlightData airports.json format: [{ iata, name, lat, lon, tz }].
Run from repo root: python3 NaarsCars/Scripts/fetch_airports_ourairports.py
Output: NaarsCars/Resources/FlightData/airports.json (overwrites).
"""
import csv
import json
import urllib.request
from pathlib import Path

URL = "https://davidmegginson.github.io/ourairports-data/airports.csv"
OUT_PATH = Path(__file__).resolve().parent.parent / "Resources" / "FlightData" / "airports.json"
MAX_AIRPORTS = 1000

# type priority: large first, then medium, then small (with scheduled service)
TYPE_ORDER = {"large_airport": 0, "medium_airport": 1, "small_airport": 2}

def main():
    print("Downloading OurAirports airports.csv...")
    req = urllib.request.Request(URL, headers={"User-Agent": "NaarsCars/1.0"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        data = resp.read().decode("utf-8")
    rows = list(csv.DictReader(data.splitlines()))
    print(f"Read {len(rows)} rows")

    seen_iata = set()
    out = []
    # Prefer large, then medium; then small with scheduled_service
    def key(r):
        t = r.get("type") or ""
        prio = TYPE_ORDER.get(t, 99)
        return (prio, t != "large_airport" and t != "medium_airport")

    for row in sorted(rows, key=key):
        iata = (row.get("iata_code") or "").strip()
        if not iata or len(iata) != 3 or iata in seen_iata:
            continue
        name = (row.get("name") or "").strip()
        try:
            lat = float(row.get("latitude_deg") or 0)
            lon = float(row.get("longitude_deg") or 0)
        except ValueError:
            continue
        seen_iata.add(iata)
        out.append({
            "iata": iata,
            "name": name,
            "lat": round(lat, 6),
            "lon": round(lon, 6),
            "tz": None
        })
        if len(out) >= MAX_AIRPORTS:
            break

    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    with open(OUT_PATH, "w", encoding="utf-8") as f:
        json.dump(out, f, indent=2, ensure_ascii=False)
    print(f"Wrote {len(out)} airports to {OUT_PATH}")

if __name__ == "__main__":
    main()

"""
create_demo_incidents.py
────────────────────────
Dev script to post 4 demo incidents of different severities through
POST /incidents/manual near a given lat/lng.

Usage:
    python create_demo_incidents.py
    python create_demo_incidents.py --lat 9.9312 --lng 76.2673
    python create_demo_incidents.py --lat 9.9312 --lng 76.2673 --url http://localhost:8000
"""

import argparse
import json
import sys
import urllib.request
import urllib.error

# Default center: Kochi city center
DEFAULT_LAT = 9.9312
DEFAULT_LNG = 76.2673
DEFAULT_BASE_URL = "http://localhost:8000"

DEMO_CASES = [
    {
        "severity": "critical",
        "emergency_type": "Cardiac Arrest",
        "department_needed": "Cardiology",
        "symptoms": ["severe chest pain", "loss of consciousness", "no pulse"],
        "victims": 1,
        "lat_offset": 0.0035,
        "lng_offset": 0.0042,
    },
    {
        "severity": "high",
        "emergency_type": "Road Traffic Accident",
        "department_needed": "Trauma",
        "symptoms": ["head trauma", "heavy arterial bleeding", "multiple fractures"],
        "victims": 2,
        "lat_offset": -0.0060,
        "lng_offset": 0.0075,
    },
    {
        "severity": "medium",
        "emergency_type": "Severe Respiratory Distress",
        "department_needed": "Pulmonology",
        "symptoms": ["acute dyspnea", "stridor", "cyanosis around lips"],
        "victims": 1,
        "lat_offset": 0.0090,
        "lng_offset": -0.0055,
    },
    {
        "severity": "low",
        "emergency_type": "Fall Injury / Fracture",
        "department_needed": "Orthopedics",
        "symptoms": ["wrist deformity", "localized severe swelling"],
        "victims": 1,
        "lat_offset": -0.0045,
        "lng_offset": -0.0080,
    },
]


def post_incident(base_url: str, payload: dict) -> dict:
    url = f"{base_url.rstrip('/')}/incidents/manual"
    req = urllib.request.Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        err_body = exc.read().decode("utf-8")
        raise RuntimeError(f"HTTP {exc.code}: {err_body}") from exc
    except Exception as exc:
        raise RuntimeError(f"Failed to connect to {url}: {exc}") from exc


def main():
    parser = argparse.ArgumentParser(
        description="Create demo incidents for testing the ambulance driver app."
    )
    parser.add_argument(
        "--lat",
        type=float,
        default=DEFAULT_LAT,
        help=f"Base latitude (default: {DEFAULT_LAT})",
    )
    parser.add_argument(
        "--lng",
        type=float,
        default=DEFAULT_LNG,
        help=f"Base longitude (default: {DEFAULT_LNG})",
    )
    parser.add_argument(
        "--url",
        type=str,
        default=DEFAULT_BASE_URL,
        help=f"Backend base URL (default: {DEFAULT_BASE_URL})",
    )

    args = parser.parse_args()

    print(f"Creating demo incidents near lat={args.lat}, lng={args.lng} at {args.url} ...\n")

    created = []
    for idx, case in enumerate(DEMO_CASES, start=1):
        payload = {
            "lat": round(args.lat + case["lat_offset"], 6),
            "lng": round(args.lng + case["lng_offset"], 6),
            "emergency_type": case["emergency_type"],
            "severity": case["severity"],
            "symptoms": case["symptoms"],
            "victims": case["victims"],
            "department_needed": case["department_needed"],
        }

        try:
            res = post_incident(args.url, payload)
            created.append(res)
            print(
                f"[{idx}/4] Created Incident #{res['id']}: "
                f"[{res['severity'].upper()}] {res['emergency_type']} "
                f"at ({res['location']['lat']}, {res['location']['lng']}) "
                f"- Dept: {res['department_needed']}"
            )
        except Exception as exc:
            print(f"[{idx}/4] FAILED to create {case['emergency_type']}: {exc}", file=sys.stderr)

    print(f"\nDone! Successfully created {len(created)}/{len(DEMO_CASES)} demo incidents.")


if __name__ == "__main__":
    main()

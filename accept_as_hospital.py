"""
accept_as_hospital.py
─────────────────────
Dev script to accept an incident broadcast on behalf of a hospital
through the real hospital accept endpoint:
POST /incidents/{incident_id}/broadcasts/{broadcast_id}/accept

Usage:
    python accept_as_hospital.py <incident_id> <hospital_id>
    python accept_as_hospital.py 1 2
    python accept_as_hospital.py 1 2 --url http://localhost:8000

Run inside Docker:
    docker compose exec app python accept_as_hospital.py <incident_id> <hospital_id>
"""

import argparse
import json
import sys
import urllib.request
import urllib.error

from app.db.session import SessionLocal
from app.models.incident_broadcast import IncidentBroadcast
from app.models.hospital import Hospital
from app.models.incident import Incident


def accept_as_hospital(incident_id: int, hospital_id: int, base_url: str) -> bool:
    db = SessionLocal()
    try:
        incident = db.get(Incident, incident_id)
        if not incident:
            print(f"[ERROR] Incident #{incident_id} not found in database.", file=sys.stderr)
            return False

        hospital = db.get(Hospital, hospital_id)
        if not hospital:
            print(f"[ERROR] Hospital #{hospital_id} not found in database.", file=sys.stderr)
            return False

        # Find pending broadcast for this hospital and incident
        broadcast = (
            db.query(IncidentBroadcast)
            .filter(
                IncidentBroadcast.incident_id == incident_id,
                IncidentBroadcast.target_type == "hospital",
                IncidentBroadcast.target_id == hospital_id,
                IncidentBroadcast.status == "pending",
            )
            .first()
        )

        if not broadcast:
            # Check if there is ANY broadcast for this hospital
            any_bc = (
                db.query(IncidentBroadcast)
                .filter(
                    IncidentBroadcast.incident_id == incident_id,
                    IncidentBroadcast.target_type == "hospital",
                    IncidentBroadcast.target_id == hospital_id,
                )
                .first()
            )
            if any_bc:
                print(
                    f"[ERROR] Broadcast #{any_bc.id} for hospital #{hospital_id} "
                    f"is not 'pending' (current status: '{any_bc.status}').",
                    file=sys.stderr,
                )
            else:
                print(
                    f"[ERROR] No broadcast found for hospital #{hospital_id} ({hospital.name}) "
                    f"on incident #{incident_id}.",
                    file=sys.stderr,
                )
            return False

        broadcast_id = broadcast.id
        print(
            f"[INFO] Found pending broadcast #{broadcast_id} for hospital #{hospital_id} "
            f"({hospital.name}) on incident #{incident_id}."
        )
    finally:
        db.close()

    endpoint = f"{base_url.rstrip('/')}/incidents/{incident_id}/broadcasts/{broadcast_id}/accept"
    print(f"[INFO] Calling real endpoint: POST {endpoint} ...")

    req = urllib.request.Request(
        endpoint,
        data=b"{}",
        headers={"Content-Type": "application/json"},
        method="POST",
    )

    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            data = json.loads(resp.read().decode())
            print(
                f"[SUCCESS] Incident #{incident_id} accepted by hospital #{hospital_id} ({hospital.name})!\n"
                f"          Status: {data.get('status')}\n"
                f"          Assigned Hospital ID: {data.get('assigned_hospital_id')}\n"
                f"          Assigned Ambulance ID: {data.get('assigned_ambulance_id')}"
            )
            return True
    except urllib.error.HTTPError as e:
        body = e.read().decode()
        print(f"[ERROR] HTTP {e.code}: {body}", file=sys.stderr)
        return False
    except Exception as e:
        print(f"[ERROR] Request failed: {e}", file=sys.stderr)
        return False


def main():
    parser = argparse.ArgumentParser(
        description="Simulate hospital acceptance of an incident broadcast."
    )
    parser.add_argument("incident_id", type=int, help="ID of the incident")
    parser.add_argument("hospital_id", type=int, help="ID of the accepting hospital")
    parser.add_argument(
        "--url",
        default="http://localhost:8000",
        help="Base URL of FastAPI backend (default: http://localhost:8000)",
    )
    args = parser.parse_args()

    success = accept_as_hospital(args.incident_id, args.hospital_id, args.url)
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()

"""
seed_hospitals.py
─────────────────
Idempotent seed script for demo hospitals and ambulances.
Safe to run multiple times — clears and re-seeds each time.

Run from the repo root:
    python seed_hospitals.py

After running this, also run:
    python seed_demo_drivers.py
to link demo drivers to these ambulances.
"""
import os
from app.db.session import SessionLocal
from app.models.hospital import Hospital
from app.models.ambulance import Ambulance

db = SessionLocal()

try:
    # Clear existing demo records
    db.query(Hospital).delete()
    db.query(Ambulance).delete()
    db.commit()

    # 1. Hospitals
    h1 = Hospital(
        name="Kochi Trauma & General Hospital",
        location="SRID=4326;POINT(76.2700 9.9390)",
        departments=["Trauma", "General Medicine", "Orthopedics"],
        is_active=True,
    )
    h2 = Hospital(
        name="Lakeside Cardiology Institute",
        location="SRID=4326;POINT(76.2800 9.9450)",
        departments=["Cardiology", "General Medicine"],
        is_active=True,
    )
    h3 = Hospital(
        name="Kerala Chest & Pulmonary Hospital",
        location="SRID=4326;POINT(76.2650 9.9520)",
        departments=["Pulmonology", "General Medicine"],
        is_active=True,
    )
    h4 = Hospital(
        name="Mother & Child Pediatrics Center",
        location="SRID=4326;POINT(76.2900 9.9600)",
        departments=["Pediatrics", "General Medicine"],
        is_active=True,
    )

    db.add_all([h1, h2, h3, h4])

    # 2. Ambulances
    # driver_name / driver_phone are gone — drivers are now linked via
    # seed_demo_drivers.py using the ambulance_driver junction table.
    a1 = Ambulance(
        registration_number="KL-07-AE-1234",
        vehicle_type="ALS",
        location="SRID=4326;POINT(76.2680 9.9320)",
        is_available=True,
    )
    a2 = Ambulance(
        registration_number="KL-07-AE-5678",
        vehicle_type="BLS",
        location="SRID=4326;POINT(76.2750 9.9400)",
        is_available=True,
    )
    a3 = Ambulance(
        registration_number="KL-01-BE-1111",
        vehicle_type="ALS",
        location="SRID=4326;POINT(76.9500 8.5300)",
        is_available=True,
    )
    a4 = Ambulance(
        registration_number="KL-01-BE-2222",
        vehicle_type="BLS",
        location="SRID=4326;POINT(76.9200 8.5200)",
        is_available=True,
    )

    db.add_all([a1, a2, a3, a4])
    db.commit()

    print("Successfully seeded 4 hospitals and 4 ambulances!")
    print("Run 'python seed_demo_drivers.py' to link drivers to ambulances.")

except Exception as e:
    db.rollback()
    print("Seeding error:", e)
finally:
    db.close()

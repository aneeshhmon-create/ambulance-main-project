import os
from sqlalchemy import text
from app.db.session import SessionLocal
from app.models.hospital import Hospital
from app.models.ambulance import Ambulance

db = SessionLocal()

try:
    # Clear existing demo records if any
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
    a1 = Ambulance(
        driver_name="Ramesh Kumar",
        driver_phone="+919846011111",
        location="SRID=4326;POINT(76.2680 9.9320)",
        is_available=True,
    )
    a2 = Ambulance(
        driver_name="Suresh Nair",
        driver_phone="+919846022222",
        location="SRID=4326;POINT(76.2750 9.9400)",
        is_available=True,
    )

    db.add_all([a1, a2])
    db.commit()

    print("Successfully seeded 4 hospitals and 2 ambulances!")

except Exception as e:
    db.rollback()
    print("Seeding error:", e)
finally:
    db.close()

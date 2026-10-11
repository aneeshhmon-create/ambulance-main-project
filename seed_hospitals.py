import os
from sqlalchemy import text
from app.db.session import SessionLocal
from app.models.hospital import Hospital
from app.models.ambulance import Ambulance

db = SessionLocal()

try:
    # 1. Hospitals (Kochi & Trivandrum)
    hospitals_data = [
        ("Kochi Trauma & General Hospital", "SRID=4326;POINT(76.2700 9.9390)", ["Trauma", "General Medicine", "Orthopedics"]),
        ("Lakeside Cardiology Institute", "SRID=4326;POINT(76.2800 9.9450)", ["Cardiology", "General Medicine"]),
        ("Kerala Chest & Pulmonary Hospital", "SRID=4326;POINT(76.2650 9.9520)", ["Pulmonology", "General Medicine"]),
        ("Mother & Child Pediatrics Center", "SRID=4326;POINT(76.2900 9.9600)", ["Pediatrics", "General Medicine"]),
        ("Trivandrum Medical College Hospital", "SRID=4326;POINT(76.9298 8.5241)", ["Trauma", "General Medicine", "Orthopedics", "Cardiology", "Pediatrics"]),
        ("KIMSHEALTH Trivandrum", "SRID=4326;POINT(76.9015 8.5085)", ["Cardiology", "Trauma", "Pulmonology", "Pediatrics", "General Medicine"]),
        ("Trivandrum General Hospital", "SRID=4326;POINT(76.9450 8.5000)", ["General Medicine", "Trauma", "Pulmonology"]),
    ]

    for name, loc, depts in hospitals_data:
        existing = db.query(Hospital).filter_by(name=name).first()
        if not existing:
            db.add(Hospital(name=name, location=loc, departments=depts, is_active=True))

    # 2. Ambulances (Kochi & Trivandrum)
    ambulances_data = [
        ("Ramesh Kumar (Kochi)", "+919846011111", "SRID=4326;POINT(76.2680 9.9320)"),
        ("Suresh Nair (Kochi)", "+919846022222", "SRID=4326;POINT(76.2750 9.9400)"),
        ("Anand V (Trivandrum)", "+919846033333", "SRID=4326;POINT(76.9500 8.5300)"),
        ("Vishnu Raj (Trivandrum)", "+919846044444", "SRID=4326;POINT(76.9200 8.5200)"),
    ]

    for driver, phone, loc in ambulances_data:
        existing = db.query(Ambulance).filter_by(driver_phone=phone).first()
        if not existing:
            db.add(Ambulance(driver_name=driver, driver_phone=phone, location=loc, is_available=True))
        else:
            existing.driver_name = driver

    db.commit()
    print("Successfully seeded hospitals and ambulances!")

except Exception as e:
    db.rollback()
    print("Seeding error:", e)
finally:
    db.close()

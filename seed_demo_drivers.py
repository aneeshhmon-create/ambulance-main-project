"""
seed_demo_drivers.py
─────────────────────
Idempotent seed script for demo drivers and their ambulance links.
Safe to run multiple times — existing records are matched by email / registration
number and updated; no duplicates are created.

════════════════════════════════════════════════════════════════
  ▶  EDIT THIS SECTION with your team's real Google account emails
════════════════════════════════════════════════════════════════
Replace the placeholder email addresses below with the Gmail addresses
your team members use to sign in with Google. Each email here will
become a valid driver account.
"""

# ── ▼ Edit these ─────────────────────────────────────────────────────────────
DRIVER_EMAILS = [
    "ambulancemainproject@gmail.com",   # ← replace with real Gmail address (driver 1)
    "driver2@example.com",   # ← replace with real Gmail address (driver 2)
    "driver3@example.com",   # ← replace with real Gmail address (driver 3)
]
# ── ▲ End of editable section ────────────────────────────────────────────────

from app.db.session import SessionLocal
from app.models.driver import Driver
from app.models.ambulance import Ambulance
from app.models.ambulance_driver import AmbulanceDriver

# ── Demo data ─────────────────────────────────────────────────────────────────
# Each entry: (name, email_index_into_DRIVER_EMAILS, phone)
DRIVERS_DATA = [
    {
        "name": "Ramesh Kumar",
        "email_idx": 0,
        "phone": "+919846011111",
        # This driver is linked to 2 ambulances: KL-07-AE-1234 and KL-07-AE-5678
        "ambulances": ["KL-07-AE-1234", "KL-07-AE-5678"],
    },
    {
        "name": "Suresh Nair",
        "email_idx": 1,
        "phone": "+919846022222",
        # This driver has exactly 1 ambulance
        "ambulances": ["KL-01-BE-1111"],
    },
    {
        "name": "Anand V",
        "email_idx": 2,
        "phone": "+919846033333",
        # This driver shares one ambulance with no one (demo only)
        "ambulances": ["KL-01-BE-2222"],
    },
]


def seed():
    db = SessionLocal()
    try:
        for data in DRIVERS_DATA:
            email = DRIVER_EMAILS[data["email_idx"]]
            name  = data["name"]
            phone = data["phone"]

            # Upsert driver (match by email)
            driver = db.query(Driver).filter_by(email=email).first()
            if not driver:
                driver = Driver(
                    name=name,
                    email=email,
                    phone=phone,
                    is_active=True,
                )
                db.add(driver)
                db.flush()  # get driver.id
                print(f"  [+] Created driver: {name} <{email}>")
            else:
                driver.name  = name
                driver.phone = phone
                print(f"  [=] Updated driver: {name} <{email}>")

            # Link to ambulances
            for reg in data["ambulances"]:
                ambulance = db.query(Ambulance).filter_by(
                    registration_number=reg
                ).first()
                if not ambulance:
                    print(f"  [!] Ambulance '{reg}' not found — run seed_hospitals.py first")
                    continue

                # Idempotent: only insert the junction row if not already there
                link = db.query(AmbulanceDriver).filter_by(
                    driver_id=driver.id,
                    ambulance_id=ambulance.id,
                ).first()
                if not link:
                    db.add(AmbulanceDriver(
                        driver_id=driver.id,
                        ambulance_id=ambulance.id,
                    ))
                    print(f"       ↳ Linked to ambulance {reg}")
                else:
                    print(f"       ↳ Already linked to {reg}")

        db.commit()
        print("\nDriver seeding complete!")
        print("─" * 55)
        print("Driver summary:")
        for data in DRIVERS_DATA:
            email = DRIVER_EMAILS[data["email_idx"]]
            ambs  = ", ".join(data["ambulances"])
            print(f"  {data['name']:20s}  {email:35s}  → {ambs}")
        print()

    except Exception as e:
        db.rollback()
        print(f"Seeding error: {e}")
        raise
    finally:
        db.close()


if __name__ == "__main__":
    print("Seeding demo drivers...")
    seed()

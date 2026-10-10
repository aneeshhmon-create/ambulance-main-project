"""
test_users_endpoint.py
───────────────────────
Verification script for Day 2 user registration endpoints:
1. POST /users - new user (201 Created)
2. POST /users - same phone again (200 OK, same ID returned)
3. POST /users - phone formatted as '+91 98765 43210' (normalizes & matches existing user)
4. POST /users - invalid phone '123' (422 Unprocessable Entity)
5. GET /users/{id} - existing user (200 OK) & non-existent user (404 Not Found)
"""

import sys
import json

if sys.platform == "win32":
    sys.stdout.reconfigure(encoding="utf-8")

from fastapi.testclient import TestClient
from app.main import app
from sqlalchemy import text
from app.db import SessionLocal
from app.models.user import User

client = TestClient(app)

# Clean up any existing test user with phone '9876543210' for a reproducible run
db = SessionLocal()
existing = db.query(User).filter(User.phone == "9876543210").first()
if existing:
    db.delete(existing)
    db.commit()
db.execute(text("SELECT setval('users_id_seq', (SELECT COALESCE(MAX(id), 1) FROM users))"))
db.commit()
db.close()

print("=" * 70)
print("TEST 1: Register New User")
print("=" * 70)
res1 = client.post("/users", json={"name": "Alice Nair", "phone": "9876543210"})
print(f"Status Code: {res1.status_code} (Expected: 201)")
print("Response JSON:")
print(json.dumps(res1.json(), indent=2))
assert res1.status_code == 201, f"Expected 201, got {res1.status_code}"
user1 = res1.json()
user_id = user1["id"]
assert user1["phone"] == "9876543210"
assert user1["name"] == "Alice Nair"

print("\n" + "=" * 70)
print("TEST 2: Same Phone Again (Must return SAME ID & status 200, update name)")
print("=" * 70)
res2 = client.post("/users", json={"name": "Alice M. Nair", "phone": "9876543210"})
print(f"Status Code: {res2.status_code} (Expected: 200)")
print("Response JSON:")
print(json.dumps(res2.json(), indent=2))
assert res2.status_code == 200, f"Expected 200, got {res2.status_code}"
user2 = res2.json()
assert user2["id"] == user_id, f"Expected same ID {user_id}, got {user2['id']}"
assert user2["name"] == "Alice M. Nair", "Name was not updated"

print("\n" + "=" * 70)
print("TEST 3: Formatted Phone '+91 98765 43210' (Must normalize & match existing)")
print("=" * 70)
res3 = client.post("/users", json={"name": "Alice M. Nair", "phone": "+91 98765 43210"})
print(f"Status Code: {res3.status_code} (Expected: 200)")
print("Response JSON:")
print(json.dumps(res3.json(), indent=2))
assert res3.status_code == 200, f"Expected 200, got {res3.status_code}"
user3 = res3.json()
assert user3["id"] == user_id, f"Expected ID {user_id}, got {user3['id']}"
assert user3["phone"] == "9876543210", f"Expected normalized phone 9876543210, got {user3['phone']}"

print("\n" + "=" * 70)
print("TEST 4: Invalid Phone '123' (Must return 422 Unprocessable Entity)")
print("=" * 70)
res4 = client.post("/users", json={"name": "Invalid User", "phone": "123"})
print(f"Status Code: {res4.status_code} (Expected: 422)")
print("Response JSON:")
print(json.dumps(res4.json(), indent=2))
assert res4.status_code == 422, f"Expected 422, got {res4.status_code}"

print("\n" + "=" * 70)
print(f"TEST 5: GET /users/{user_id} (Existing User)")
print("=" * 70)
res5 = client.get(f"/users/{user_id}")
print(f"Status Code: {res5.status_code} (Expected: 200)")
print("Response JSON:")
print(json.dumps(res5.json(), indent=2))
assert res5.status_code == 200
assert res5.json()["id"] == user_id

print("\n" + "=" * 70)
print("TEST 6: GET /users/999999 (Non-existent User -> 404)")
print("=" * 70)
res6 = client.get("/users/999999")
print(f"Status Code: {res6.status_code} (Expected: 404)")
print("Response JSON:")
print(json.dumps(res6.json(), indent=2))
assert res6.status_code == 404

print("\n" + "=" * 70)
print("ALL TESTS PASSED SUCCESSFULLY! ALL REQUIREMENTS VERIFIED.")
print("=" * 70)

import os
import sys
import json

if sys.platform == "win32":
    sys.stdout.reconfigure(encoding="utf-8")

from fastapi.testclient import TestClient
from app.main import app
from app.services.extraction_service import extract_severity

client = TestClient(app)

print("=" * 60)
print("TEST 1: Direct LLM Extraction on Transcripts")
print("=" * 60)

with open("scratch_transcripts.json", "r", encoding="utf-8") as f:
    transcripts = json.load(f)

for name, data in transcripts.items():
    t = data["transcript"]
    lang = data["detected_language"]
    print(f"\n--- Clip: {name} (lang: {lang}) ---")
    print(f"Transcript: {t}")
    extracted = extract_severity(t)
    print(f"Extracted: {json.dumps(extracted, indent=2)}")

print("\n" + "=" * 60)
print("TEST 2: End-to-End POST /incidents with Audio Upload")
print("=" * 60)

audio_dir = r"C:\Users\Midhul\Downloads\Telegram Desktop"
test_clips = ["stt1.ogg", "stt2.ogg", "stt3.ogg", "stt4.ogg"]
# Location near Kochi city center: lat 9.9350, lng 76.2690
lat, lng = 9.9350, 76.2690

responses = {}
for clip_name in test_clips:
    clip_path = os.path.join(audio_dir, clip_name)
    if not os.path.exists(clip_path):
        print(f"Skipping {clip_name}, not found.")
        continue

    print(f"\n>>> Uploading {clip_name} to POST /incidents ...")
    with open(clip_path, "rb") as audio_file:
        response = client.post(
            "/incidents",
            data={"lat": lat, "lng": lng, "user_id": 1},
            files={"audio_file": (clip_name, audio_file, "audio/ogg")},
        )

    print(f"HTTP Status: {response.status_code}")
    if response.status_code == 201:
        res_json = response.json()
        responses[clip_name] = res_json
        print(f"Incident ID: {res_json['id']}")
        print(f"Emergency Type: {res_json['emergency_type']}")
        print(f"Severity: {res_json['severity']}")
        print(f"Dept Needed: {res_json['department_needed']}")
        print(f"Assigned Ambulance ID: {res_json['assigned_ambulance_id']}")
        print(f"Broadcasts count: {len(res_json['broadcasts'])}")
        print(f"Broadcast details: {res_json['broadcasts']}")
    else:
        print("Error body:", response.text)

# Save full results for inspection
with open("test_end_to_end_results.json", "w", encoding="utf-8") as f:
    json.dump(responses, f, ensure_ascii=False, indent=2)

print("\nAll tests finished! Saved full output to test_end_to_end_results.json")

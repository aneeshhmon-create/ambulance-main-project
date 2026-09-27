import os
import json
from app.services.stt_service import transcribe_audio

folder = r"C:\Users\Midhul\Downloads\Telegram Desktop"
files = ["stt1.ogg", "stt2.ogg", "stt3.ogg", "stt4.ogg"]

results = {}
for f in files:
    path = os.path.join(folder, f)
    if os.path.exists(path):
        print(f"Transcribing {f} ...")
        res = transcribe_audio(path)
        results[f] = res
        print(f"Done {f}: lang={res['detected_language']}, duration={res['duration_seconds']}s")
    else:
        print(f"Missing file: {path}")

with open("scratch_transcripts.json", "w", encoding="utf-8") as fp:
    json.dump(results, fp, ensure_ascii=False, indent=2)

print("Saved all transcripts successfully to scratch_transcripts.json")

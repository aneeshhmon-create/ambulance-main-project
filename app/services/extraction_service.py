"""
app/services/extraction_service.py
───────────────────────────────────
Severity and incident feature extraction layer powered by Google Gemini LLM.

Extracts structured medical triage and emergency dispatch parameters from
raw audio transcripts (Malayalam, English, or Code-Switched).

Fields extracted:
  - emergency_type   : accident / cardiac / respiratory / fall / burn / other
  - severity         : low / medium / high / critical
  - symptoms         : list[str]
  - victims          : int (default 1)
  - department_needed: one of valid hospital departments
"""

import os
import json
import logging
from typing import Any

from dotenv import load_dotenv
from google import genai
from google.genai import types

load_dotenv()
load_dotenv(os.path.expanduser("~/.env"))

logger = logging.getLogger(__name__)

# Valid hospital departments in the dispatch system
VALID_DEPARTMENTS = [
    "Trauma",
    "Cardiology",
    "General Medicine",
    "Pediatrics",
    "Neurology",
    "Pulmonology",
    "Orthopedics",
    "Burn Care",
]

# Valid severities
VALID_SEVERITIES = {"low", "medium", "high", "critical"}

# Safe fallback dictionary if AI extraction fails for any reason
SAFE_FALLBACK: dict[str, Any] = {
    "emergency_type": "unspecified",
    "severity": "medium",
    "symptoms": [],
    "victims": 1,
    "department_needed": "General Medicine",
}

# Candidate models in priority order with automatic fallback
_CANDIDATE_MODELS = [
    "gemini-flash-latest",
    "gemini-flash-lite-latest",
    "gemini-2.5-flash",
    "gemini-2.5-flash-lite",
    "gemini-2.5-pro",
]


def _build_prompt(transcript: str) -> str:
    departments_str = ", ".join(f'"{d}"' for d in VALID_DEPARTMENTS)
    return f"""You are an emergency medical triage dispatch AI for an ambulance service in Kerala, India.
Analyze the following transcript of an emergency call (which may be in English, Malayalam, or mixed Malayalam-English).
Extract structured emergency information according to these strict rules:

1. "emergency_type": string, one of: "accident", "cardiac", "respiratory", "fall", "burn", "other"
2. "severity": string, exactly one of: "low", "medium", "high", "critical"
   - "critical": unconscious, severe chest pain/cardiac arrest, massive bleeding, severe head trauma, not breathing
   - "high": serious fractures, deep wounds, difficulty breathing, multiple victims
   - "medium": moderate pain, stable vitals, single non-life-threatening injury
   - "low": minor cuts, mild fever, non-urgent assistance
3. "symptoms": array of strings describing symptoms or conditions mentioned (in English)
4. "victims": integer count of injured/affected persons mentioned (default 1 if not specified)
5. "department_needed": string, MUST be selected from ONLY this allowed list: [{departments_str}]
   - Vehicle accidents, severe trauma, bleeding -> "Trauma"
   - Heart attacks, chest pain -> "Cardiology"
   - Breathing difficulty, asthma -> "Pulmonology"
   - Bone breaks -> "Orthopedics"
   - Children -> "Pediatrics"
   - Burns -> "Burn Care"
   - General illnesses / unknown -> "General Medicine"

Return ONLY a valid JSON object with these 5 keys and NO surrounding markdown, commentary, or text.

TRANSCRIPT:
\"\"\"{transcript}\"\"\"
"""


def extract_severity(transcript: str) -> dict[str, Any]:
    """
    Extract structured emergency metadata from a transcript using Gemini.

    Guarantees:
      - Always returns a dict with keys: emergency_type, severity, symptoms, victims, department_needed.
      - Never raises exceptions: any API, network, JSON parsing, or validation error
        safely defaults to SAFE_FALLBACK.
    """
    if not transcript or not transcript.strip():
        logger.warning("[Extraction] Empty transcript received. Returning fallback.")
        return dict(SAFE_FALLBACK)

    api_key = os.environ.get("GEMINI_API_KEY") or os.environ.get("GOOGLE_API_KEY")
    if not api_key:
        logger.warning(
            "[Extraction] Neither GEMINI_API_KEY nor GOOGLE_API_KEY found in environment. "
            "Returning safe fallback."
        )
        return dict(SAFE_FALLBACK)

    try:
        client = genai.Client(api_key=api_key)
        prompt = _build_prompt(transcript)

        response = None
        last_error = None
        for model_name in _CANDIDATE_MODELS:
            try:
                res = client.models.generate_content(
                    model=model_name,
                    contents=prompt,
                    config=types.GenerateContentConfig(
                        response_mime_type="application/json",
                        temperature=0.1,
                    ),
                )
                if res and res.text:
                    response = res
                    logger.info("[Extraction] Successfully used model: %s", model_name)
                    break
            except Exception as e:
                last_error = e
                logger.warning(
                    "[Extraction] Model '%s' returned error (%s). Trying fallback candidate...",
                    model_name, e,
                )

        if not response or not response.text:
            raise RuntimeError(f"All candidate models failed. Last error: {last_error}")

        raw_text = response.text or ""
        # Clean any potential backticks or whitespace
        cleaned = raw_text.strip()
        if cleaned.startswith("```json"):
            cleaned = cleaned[7:]
        if cleaned.startswith("```"):
            cleaned = cleaned[3:]
        if cleaned.endswith("```"):
            cleaned = cleaned[:-3]
        cleaned = cleaned.strip()

        data = json.loads(cleaned)

        # Validate and sanitize fields
        emergency_type = str(data.get("emergency_type", "unspecified")).lower()
        
        severity = str(data.get("severity", "medium")).lower()
        if severity not in VALID_SEVERITIES:
            severity = "medium"

        raw_symptoms = data.get("symptoms", [])
        if isinstance(raw_symptoms, list):
            symptoms = [str(s).strip() for s in raw_symptoms if s]
        else:
            symptoms = [str(raw_symptoms)] if raw_symptoms else []

        try:
            victims = int(data.get("victims", 1))
            if victims < 1:
                victims = 1
        except (ValueError, TypeError):
            victims = 1

        dept = str(data.get("department_needed", "General Medicine"))
        # Match against valid departments case-insensitively
        matched_dept = next(
            (d for d in VALID_DEPARTMENTS if d.lower() == dept.lower()),
            "General Medicine",
        )

        result = {
            "emergency_type": emergency_type,
            "severity": severity,
            "symptoms": symptoms,
            "victims": victims,
            "department_needed": matched_dept,
        }
        logger.info("[Extraction] Successfully extracted metadata: %s", result)
        return result

    except Exception as exc:
        logger.exception(
            "[Extraction] LLM extraction or parsing failed (%s). Returning safe fallback.",
            exc,
        )
        return dict(SAFE_FALLBACK)

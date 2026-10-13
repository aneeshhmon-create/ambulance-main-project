"""
app/services/stt_service.py
───────────────────────────
Speech-to-text via Gemini (replaces the local Whisper pipeline).

Flow
────
1. transcribe_only():   audio -> Malayalam/English text   (gemini-3.5-transcribe,
                        language hints ml-IN + en-IN, "smart" mode)
2. translate_to_english(): text -> fluent English          (gemini-3.8-flash)

The audio is sent inline (base64), so there is no upload / delete round trip.
Nothing runs locally: no GPU, ffmpeg or model download needed.

Env overrides: GEMINI_TRANSCRIBE_MODEL, GEMINI_TRANSLATE_MODEL.
"""

import base64
import logging
import os
import time

from app.services.gemini_client import get_client

logger = logging.getLogger(__name__)

TRANSCRIBE_MODEL = os.environ.get("GEMINI_TRANSCRIBE_MODEL", "gemini-3.5-transcribe")
TRANSLATE_MODEL = os.environ.get("GEMINI_TRANSLATE_MODEL", "gemini-3.8-flash")

_TRANSCRIBE_TIMEOUT_S = 30.0
_TRANSLATE_TIMEOUT_S = 30.0

# File extension -> mime type accepted by the interactions API.
_MIME_BY_EXT = {
    ".ogg": "audio/ogg",
    ".oga": "audio/ogg",
    ".opus": "audio/opus",
    ".m4a": "audio/m4a",
    ".mp4": "audio/m4a",
    ".aac": "audio/aac",
    ".mp3": "audio/mp3",
    ".wav": "audio/wav",
    ".flac": "audio/flac",
    ".webm": "audio/webm",
}


def _has_malayalam(text: str) -> bool:
    return any("ഀ" <= ch <= "ൿ" for ch in text)


def _transcribe_call(audio_b64: str, mime: str, language_codes: list[str]) -> str:
    res = get_client().interactions.create(
        model=TRANSCRIBE_MODEL,
        input={"type": "audio", "data": audio_b64, "mime_type": mime},
        generation_config={
            "transcription_config": {"language_codes": language_codes, "mode": "smart"},
        },
        timeout=_TRANSCRIBE_TIMEOUT_S,
    )
    return (res.output_text or "").strip()


def transcribe_only(file_path: str) -> dict:
    """
    Transcribe audio in its spoken language (Malayalam script for Malayalam).

    Returns: {"original_transcript": str, "detected_language": "ml"|"en",
              "duration_seconds": float}
    """
    t0 = time.perf_counter()
    ext = os.path.splitext(file_path)[1].lower()
    mime = _MIME_BY_EXT.get(ext, "audio/ogg")
    with open(file_path, "rb") as fh:
        audio_b64 = base64.b64encode(fh.read()).decode("ascii")

    try:
        text = _transcribe_call(audio_b64, mime, ["ml-IN", "en-IN"])
    except Exception as exc:
        # Some deployments may only accept a single language code.
        logger.warning("[STT] ml-IN+en-IN failed (%s); retrying with ml-IN only.", exc)
        text = _transcribe_call(audio_b64, mime, ["ml-IN"])

    duration = round(time.perf_counter() - t0, 2)
    lang = "ml" if _has_malayalam(text) else "en"
    logger.info("[STT] Gemini transcription done in %.2fs (lang=%s)", duration, lang)
    print(f"[STT] Gemini transcription took {duration}s (lang={lang})")
    return {"original_transcript": text, "detected_language": lang, "duration_seconds": duration}


def translate_to_english(text: str) -> str:
    """Translate to English. Returns the input unchanged if it has no Malayalam or on failure."""
    if not text or not _has_malayalam(text):
        return text
    t0 = time.perf_counter()
    try:
        res = get_client().interactions.create(
            model=TRANSLATE_MODEL,
            input=(
                "You are a professional Malayalam-to-English translator.\n"
                "Translate the following Malayalam text into fluent, natural English.\n"
                "Keep the meaning accurate and preserve the tone.\n"
                "Provide ONLY the English translation, nothing else.\n\n"
                f"Malayalam text:\n{text}"
            ),
            generation_config={"temperature": 0.1, "thinking_level": "low"},
            timeout=_TRANSLATE_TIMEOUT_S,
        )
        english = (res.output_text or "").strip()
        logger.info("[STT] Translation done in %.2fs", time.perf_counter() - t0)
        return english or text
    except Exception as exc:
        logger.warning("[STT] Translation failed (%s); keeping original transcript.", exc)
        return text


def transcribe_audio(file_path: str) -> dict:
    """
    Transcribe + translate (sequential). Kept for the test endpoint / scripts.

    Returns: transcript (English), original_transcript, detected_language,
             duration_seconds.
    """
    t0 = time.perf_counter()
    result = transcribe_only(file_path)
    english = translate_to_english(result["original_transcript"])
    return {
        "transcript": english,
        "original_transcript": result["original_transcript"],
        "detected_language": result["detected_language"],
        "duration_seconds": round(time.perf_counter() - t0, 2),
    }

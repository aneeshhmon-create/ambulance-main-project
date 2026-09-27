"""
app/routers/test_transcribe.py
──────────────────────────────
Temporary validation endpoint — Week 1 / Day 5 only.

POST /test/transcribe
    • Accepts an audio file upload (mp3 / wav / m4a — any ffmpeg-decodable
      format works).
    • Runs faster-whisper transcription.
    • Returns the raw transcript, detected language, and timing.

Wire-up plan:
    Day 6 → remove this router; pipe stt_service.transcribe_audio()
            into POST /incidents when a voice attachment is present.

Remove or gate behind APP_ENV != "production" before going live.
"""

import os
import shutil
import tempfile
import logging

from fastapi import APIRouter, HTTPException, UploadFile, File, status

from app.services.stt_service import transcribe_audio

logger = logging.getLogger(__name__)

router = APIRouter()

# Formats faster-whisper / ffmpeg can handle reliably
_ALLOWED_EXTENSIONS = {".mp3", ".wav", ".m4a", ".flac", ".ogg", ".webm"}


@router.post(
    "/transcribe",
    summary="[TEST] Transcribe an audio file",
    description=(
        "Upload an audio clip (mp3/wav/m4a) and receive the raw Whisper "
        "transcript plus the auto-detected language. "
        "**Temporary endpoint — Day 5 accuracy validation only.**"
    ),
    tags=["Test / Validation"],
)
async def test_transcribe(
    audio_file: UploadFile = File(
        ...,
        description="Audio file to transcribe. Supported: mp3, wav, m4a, flac, ogg, webm.",
    ),
):
    """
    Accept an audio upload, write it to a temp file, run STT, return results.

    The temp file is deleted immediately after transcription regardless of
    success or failure.
    """
    # ── Validate extension ─────────────────────────────────────────────────────
    _, ext = os.path.splitext(audio_file.filename or "")
    if ext.lower() not in _ALLOWED_EXTENSIONS:
        raise HTTPException(
            status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            detail=(
                f"Unsupported file type '{ext}'. "
                f"Allowed: {', '.join(sorted(_ALLOWED_EXTENSIONS))}"
            ),
        )

    # ── Save to a named temp file (faster-whisper needs a file path) ───────────
    tmp_path: str | None = None
    try:
        with tempfile.NamedTemporaryFile(
            suffix=ext.lower(), delete=False
        ) as tmp:
            shutil.copyfileobj(audio_file.file, tmp)
            tmp_path = tmp.name

        logger.info(
            "[test_transcribe] Saved upload '%s' → tmp '%s' (%.1f KB)",
            audio_file.filename,
            tmp_path,
            os.path.getsize(tmp_path) / 1024,
        )

        # ── Run transcription ──────────────────────────────────────────────────
        result = transcribe_audio(tmp_path)

    except Exception as exc:
        logger.exception("[test_transcribe] Transcription failed: %s", exc)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Transcription failed: {exc}",
        )
    finally:
        # Always clean up the temp file
        if tmp_path and os.path.exists(tmp_path):
            os.unlink(tmp_path)

    return {
        "filename": audio_file.filename,
        "transcript": result["transcript"],
        "detected_language": result["detected_language"],
        "transcription_took_seconds": result["duration_seconds"],
        "note": "Temporary endpoint — Day 5 accuracy validation only.",
    }

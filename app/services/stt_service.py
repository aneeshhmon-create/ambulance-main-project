"""
app/services/stt_service.py
───────────────────────────
Speech-to-text service powered by faster-whisper.

Design decisions
────────────────
• Model: "large-v3-turbo"
    - Distilled from large-v3: ~6x faster than large-v3, ~same disk size as medium.
    - Dramatically better Malayalam accuracy vs. medium (which has very limited
      Dravidian language data and frequently hallucinates on Malayalam).

• beam_size=1 (greedy decoding):
    - 3-5x faster than beam_size=5 on CPU with negligible accuracy loss.

• condition_on_previous_text=False:
    - Prevents Whisper feeding its own hallucinated output back as context,
      which caused 3-minute runaway transcriptions on Malayalam audio.

• temperature=0:
    - Deterministic, no sampling fallback. Faster.

• vad_filter=True:
    - Strips silence/noise from phone-call audio before inference.

• Language strategy — post-transcription re-run:
    - First pass: language=None (auto-detect).
    - If auto-detect returns a non-allowed language (e.g. Tamil for a Malayalam
      clip — a known large-v3-turbo false positive due to Dravidian acoustic
      similarity), immediately re-run with language="ml" forced.
    - This is more reliable than using detect_language() which has API
      inconsistencies with certain audio formats in faster-whisper 1.x.
    - Re-run only happens in the false-positive case (~1 extra pass, ~30s).
    - Allowed languages for this domain: {"ml", "en"} — Kerala emergency dispatch.

• Model loaded ONCE at module level — not per request.
• GPU float16 if CUDA available, CPU int8 otherwise.
"""

import os
import time
import logging

from faster_whisper import WhisperModel

logger = logging.getLogger(__name__)


# ── Model selection ───────────────────────────────────────────────────────────
# Use locally downloaded full large-v3 model
_LOCAL_MODEL_DIR = os.path.abspath(
    os.path.join(os.path.dirname(__file__), "..", "..", "models", "large-v3")
)
_MODEL_SIZE = _LOCAL_MODEL_DIR if os.path.isdir(_LOCAL_MODEL_DIR) else "large-v3"

# ── Device / precision ────────────────────────────────────────────────────────
def _select_device_and_compute() -> tuple[str, str]:
    try:
        import torch
        if torch.cuda.is_available():
            logger.info("CUDA detected -- loading '%s' on GPU (float16).", _MODEL_SIZE)
            return "cuda", "float16"
    except ImportError:
        pass
    logger.info("No GPU -- loading '%s' on CPU (int8).", _MODEL_SIZE)
    return "cpu", "int8"


_device, _compute_type = _select_device_and_compute()

# ── Module-level model load ───────────────────────────────────────────────────
logger.info("Loading faster-whisper model '%s' ...", _MODEL_SIZE)
_model = WhisperModel(_MODEL_SIZE, device=_device, compute_type=_compute_type)
logger.info("faster-whisper model '%s' ready.", _MODEL_SIZE)


# ── Domain constraints ────────────────────────────────────────────────────────
# Kerala emergency dispatch: callers only speak Malayalam or English.
# Tamil detection = false positive (acoustic similarity). Always re-run as ml.
_ALLOWED_LANGUAGES = frozenset({"ml", "en"})


# ── Shared transcribe call ────────────────────────────────────────────────────
def _run_transcribe(file_path: str, language: str | None):
    """Single transcribe call with consistent settings."""
    segments, info = _model.transcribe(
        file_path,
        language=language,
        beam_size=1,                      # greedy: 3-5x faster on CPU
        vad_filter=True,                  # strip silence / phone noise
        condition_on_previous_text=False, # prevents hallucination loops
        temperature=0,                    # deterministic, no sampling fallback
    )
    transcript = " ".join(seg.text.strip() for seg in segments)
    return transcript, info


# ── Public API ────────────────────────────────────────────────────────────────
def transcribe_audio(file_path: str) -> dict:
    """
    Transcribe an audio file and return the transcript plus detected language.

    Strategy
    --------
    1. Auto-detect language (language=None).
    2. If Whisper picks a language outside {"ml", "en"} (e.g. Tamil as a false
       positive for Malayalam), re-run immediately with language="ml" forced.
       This adds ~30 s only in the rare false-positive case.

    Parameters
    ----------
    file_path : str
        Path to the audio file. Supports WAV, MP3, M4A, OGG, FLAC, and any
        format ffmpeg can decode.

    Returns
    -------
    dict
        transcript        (str)   -- full transcribed text.
        detected_language (str)   -- "ml" or "en" (corrected if needed).
        duration_seconds  (float) -- wall-clock transcription time.
    """
    t_start = time.perf_counter()
    print(f"[STT] >> Transcription started  -- {time.strftime('%H:%M:%S')}")
    logger.info("[STT] Starting transcription: %s", file_path)

    # ── Pass 1: auto-detect ───────────────────────────────────────────────────
    transcript, info = _run_transcribe(file_path, language=None)
    final_language = info.language

    # ── Pass 2 (if needed): re-run with forced Malayalam ─────────────────────
    if info.language not in _ALLOWED_LANGUAGES:
        logger.warning(
            "[STT] Auto-detect chose '%s' (not in allowed set %s). "
            "Re-running with language='ml'.",
            info.language, set(_ALLOWED_LANGUAGES),
        )
        print(
            f"[STT] [LANG OVERRIDE] '{info.language}' not allowed "
            f"-- re-running as 'ml' (Kerala domain)"
        )
        transcript, info2 = _run_transcribe(file_path, language="ml")
        final_language = "ml"

    t_end = time.perf_counter()
    duration = round(t_end - t_start, 2)

    print(
        f"[STT] [DONE] Transcription finished -- {time.strftime('%H:%M:%S')} "
        f"(took {duration}s, lang: {final_language!r})"
    )
    logger.info(
        "[STT] Done in %.2fs | language=%s | whisper_raw=%s",
        duration, final_language, info.language,
    )

    return {
        "transcript": transcript,
        "detected_language": final_language,
        "duration_seconds": duration,
    }

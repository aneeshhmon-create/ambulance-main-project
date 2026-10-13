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

• Language strategy — restricted detection, single pass:
    - detect_language() probabilities are filtered to {"ml", "en"} (Kerala
      emergency dispatch), so Hindi/Tamil can never be chosen, and the clip is
      transcribed exactly once (no ~30 s re-run pass).

• Model loaded ONCE at module level — not per request.
• Device: CUDA detected via CTranslate2 (no torch needed), float16; falls back to
  CPU int8 if the GPU libs (cuBLAS/cuDNN) fail to load. Env overrides:
  WHISPER_MODEL, WHISPER_DEVICE (cpu|cuda). warmup() runs at app startup.
"""

import os
import time
import logging
import subprocess

import numpy as np

from faster_whisper import WhisperModel

logger = logging.getLogger(__name__)


# ── Model selection ───────────────────────────────────────────────────────────
# Override with WHISPER_MODEL (a size name like "large-v3" or a local path).
# Default is large-v3-turbo: ~6x faster than large-v3 with near-identical accuracy.
_LOCAL_MODEL_DIR = os.path.abspath(
    os.path.join(os.path.dirname(__file__), "..", "..", "models", "large-v3-turbo")
)
_MODEL_SIZE = os.environ.get("WHISPER_MODEL") or (
    _LOCAL_MODEL_DIR if os.path.isdir(_LOCAL_MODEL_DIR) else "large-v3-turbo"
)


# ── Device / precision ────────────────────────────────────────────────────────
def _cuda_available() -> bool:
    """Ask CTranslate2 directly -- faster-whisper does not need torch."""
    try:
        import ctranslate2
        return ctranslate2.get_cuda_device_count() > 0
    except Exception:
        return False


def _preload_cuda_libs() -> None:
    """
    Load cuBLAS/cuDNN shipped by the nvidia-*-cu12 pip packages, so no manual
    LD_LIBRARY_PATH is needed. Silently does nothing if they aren't installed.
    """
    import ctypes
    import glob
    import importlib

    for mod, pattern in (("nvidia.cublas.lib", "libcublas*.so*"), ("nvidia.cudnn.lib", "libcudnn*.so*")):
        try:
            paths = list(importlib.import_module(mod).__path__)
        except Exception:
            continue
        for d in paths:
            # cublasLt / cudnn sub-libs first-load order is handled by RTLD_GLOBAL + lazy lookup
            for so in sorted(glob.glob(os.path.join(d, pattern))):
                try:
                    ctypes.CDLL(so, mode=ctypes.RTLD_GLOBAL)
                except OSError:
                    pass


def _gpu_selftest(model: WhisperModel) -> None:
    """Tiny inference: model load succeeds even if cuBLAS/cuDNN are missing."""
    segs, _ = model.transcribe(np.zeros(16000, dtype=np.float32), language="en", beam_size=1)
    list(segs)


def _load_model() -> tuple[WhisperModel, str, str]:
    forced = (os.environ.get("WHISPER_DEVICE") or "").lower()
    if forced != "cpu" and (forced == "cuda" or _cuda_available()):
        _preload_cuda_libs()
        for compute in ("float16", "int8_float16"):
            try:
                logger.info("Loading '%s' on GPU (%s) ...", _MODEL_SIZE, compute)
                model = WhisperModel(_MODEL_SIZE, device="cuda", compute_type=compute)
                _gpu_selftest(model)
                return model, "cuda", compute
            except Exception as exc:  # missing cuDNN/cuBLAS, out of memory, ...
                logger.warning("GPU load failed (%s: %s).", compute, exc)
        logger.warning("Falling back to CPU -- transcription will be much slower.")
    logger.info("Loading '%s' on CPU (int8) ...", _MODEL_SIZE)
    model = WhisperModel(
        _MODEL_SIZE,
        device="cpu",
        compute_type="int8",
        cpu_threads=min(os.cpu_count() or 4, 16),
    )
    return model, "cpu", "int8"


_model, _device, _compute_type = _load_model()
logger.info("faster-whisper '%s' ready on %s (%s).", _MODEL_SIZE, _device, _compute_type)
print(f"[STT] model={_MODEL_SIZE!r} device={_device} compute={_compute_type}")


# ── Domain constraints ────────────────────────────────────────────────────────
# Kerala emergency dispatch: callers only speak Malayalam or English.
_ALLOWED_LANGUAGES = frozenset({"ml", "en"})
_DEFAULT_LANGUAGE = "ml"


def _decode_audio(file_path: str) -> np.ndarray:
    """
    Decode any ffmpeg-readable file to 16 kHz mono float32.

    Uses the ffmpeg CLI directly: faster-whisper 1.1.1's built-in decoder calls
    av.open(metadata_errors=...), which newer PyAV releases reject. Decoding
    once here also avoids decoding twice (language detection + transcription).
    """
    proc = subprocess.run(
        ["ffmpeg", "-nostdin", "-v", "error", "-i", file_path,
         "-f", "s16le", "-ac", "1", "-ar", "16000", "-"],
        capture_output=True,
    )
    if proc.returncode != 0:
        raise RuntimeError(f"ffmpeg failed to decode audio: {proc.stderr.decode(errors='replace')[:300]}")
    return np.frombuffer(proc.stdout, dtype=np.int16).astype(np.float32) / 32768.0


def _pick_language(audio: np.ndarray) -> str:
    """
    Detect the language among {ml, en} only, so Whisper's guess of Hindi/Tamil
    (acoustically similar / noisy clips) can never be chosen, and the clip is
    transcribed exactly once. Costs one encoder pass over the first 30 s.
    """
    try:
        _, _, all_probs = _model.detect_language(audio[: 30 * 16000])
        probs = {lang: p for lang, p in all_probs if lang in _ALLOWED_LANGUAGES}
        if probs:
            return max(probs, key=probs.get)
    except Exception as exc:
        logger.warning("[STT] Language detection failed (%s); using '%s'.", exc, _DEFAULT_LANGUAGE)
    return _DEFAULT_LANGUAGE


def warmup() -> None:
    """Run a tiny dummy inference so CUDA init / kernel load happens at startup."""
    try:
        t0 = time.perf_counter()
        segs, _ = _model.transcribe(np.zeros(16000, dtype=np.float32), language="en", beam_size=1)
        list(segs)
        logger.info("[STT] Warm-up done in %.2fs", time.perf_counter() - t0)
    except Exception as exc:
        logger.warning("[STT] Warm-up skipped: %s", exc)


# ── Shared transcribe call ────────────────────────────────────────────────────
def _run_transcribe(audio: np.ndarray, language: str):
    """Single transcribe call with consistent settings."""
    segments, info = _model.transcribe(
        audio,
        language=language,
        beam_size=1,                      # greedy: fastest
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
    1. Detect language restricted to {"ml", "en"} (never Hindi/Tamil).
    2. Transcribe once with that language -- no re-run pass.

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

    audio = _decode_audio(file_path)
    final_language = _pick_language(audio)
    t_detect = time.perf_counter()
    transcript, _info = _run_transcribe(audio, language=final_language)

    t_end = time.perf_counter()
    duration = round(t_end - t_start, 2)

    print(
        f"[STT] [DONE] Transcription finished -- {time.strftime('%H:%M:%S')} "
        f"(took {duration}s, lang: {final_language!r})"
    )
    logger.info(
        "[STT] Done in %.2fs (lang detect %.2fs) | language=%s",
        duration, t_detect - t_start, final_language,
    )

    return {
        "transcript": transcript,
        "detected_language": final_language,
        "duration_seconds": duration,
    }

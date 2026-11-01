"""
app/services/gemini_client.py
─────────────────────────────
One shared google-genai client (reuses the HTTP connection pool across requests).
"""

import os
import threading

from dotenv import load_dotenv
from google import genai
from google.genai import types

load_dotenv()
load_dotenv(os.path.expanduser("~/.env"))

_lock = threading.Lock()
_client: genai.Client | None = None
_client_key: str | None = None


def get_api_key() -> str | None:
    return os.environ.get("GEMINI_API_KEY") or os.environ.get("GOOGLE_API_KEY")


def get_client(timeout_ms: int = 30000) -> genai.Client:
    """Return the shared client. Raises RuntimeError if no API key is configured."""
    global _client, _client_key
    api_key = get_api_key()
    if not api_key:
        raise RuntimeError("Neither GEMINI_API_KEY nor GOOGLE_API_KEY is set in the environment.")
    with _lock:
        if _client is None or _client_key != api_key:
            _client = genai.Client(
                api_key=api_key,
                http_options=types.HttpOptions(timeout=timeout_ms),
            )
            _client_key = api_key
        return _client

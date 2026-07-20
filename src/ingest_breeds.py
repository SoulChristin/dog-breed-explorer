"""Fetch dog breeds from TheDogAPI and persist the raw payload, untouched.

Writes to data/raw/run_date=<UTC date>/breeds.json. Re-running on the same day
overwrites that file, so the run is idempotent.

The payload is validated but never mutated. validate() parses it to check its
shape and row count, then discards the parsed object; what reaches disk is the
original response text, byte for byte. Parsing for a decision is not the same
as parsing for persistence, and only the latter would break the raw layer.

Requires DOG_API_KEY in the environment. The key is never written to disk.
"""

from __future__ import annotations

import json
import os
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

import requests

API_URL = "https://api.thedogapi.com/v1/breeds"
TIMEOUT_SECONDS = 30
MAX_ATTEMPTS = 3
MIN_BREEDS = 500                  # live count is 628 as of 2026-07-19
RETRYABLE_STATUS = {429, 500, 502, 503, 504}   # transient; the rest are ours to fix
REPO_ROOT = Path(__file__).resolve().parents[1]


def fetch_breeds(api_key: str) -> str:
    """Return the response body as text, retrying transient failures.

    Only 429 and 5xx are retried: rate limits and server errors genuinely pass.
    A 401/403/404 raises immediately, because no amount of waiting fixes a bad
    key or a wrong URL - this API returns 403 for both a missing and an invalid
    key, so the message points at DOG_API_KEY rather than leaving the caller to
    guess.

    Returns text rather than parsed JSON so the caller can persist the exact
    bytes the API sent.
    """
    last_error = None
    for attempt in range(1, MAX_ATTEMPTS + 1):
        try:
            response = requests.get(
                API_URL,
                headers={"x-api-key": api_key},
                timeout=TIMEOUT_SECONDS,
            )
            if response.status_code == 200:
                return response.text
            if response.status_code not in RETRYABLE_STATUS:
                raise RuntimeError(
                    f"HTTP {response.status_code} will not resolve by retrying - "
                    f"check DOG_API_KEY or the endpoint: {response.text[:200]}"
                )
            last_error = f"HTTP {response.status_code}"
        except requests.RequestException as exc:
            last_error = f"{type(exc).__name__}: {exc}"

        if attempt < MAX_ATTEMPTS:
            backoff = 2 ** attempt        # 2s, then 4s
            print(f"attempt {attempt}/{MAX_ATTEMPTS} failed ({last_error}); "
                  f"retrying in {backoff}s", file=sys.stderr)
            time.sleep(backoff)

    raise RuntimeError(f"giving up after {MAX_ATTEMPTS} attempts - {last_error}")


def validate(payload_text: str) -> int:
    """Refuse to persist a payload that looks truncated or malformed.

    Parses the payload to inspect it and returns only the breed count - the
    parsed object is deliberately discarded, so nothing derived from it can
    reach disk. A missed day is recoverable by re-running; a raw layer silently
    poisoned with a partial response is not.
    """
    breeds = json.loads(payload_text)
    # Local only, never returned or written. A truncated response dies here,
    # because json.loads raises on malformed input before anything is persisted.
    if not isinstance(breeds, list):
        raise ValueError(f"expected a JSON array, got {type(breeds).__name__}")
    if len(breeds) < MIN_BREEDS:
        raise ValueError(
            f"only {len(breeds)} breeds (floor is {MIN_BREEDS}) - refusing to "
            "persist what looks like a partial response"
        )
    return len(breeds)


def main() -> None:
    api_key = os.environ.get("DOG_API_KEY")
    if not api_key:
        raise RuntimeError("DOG_API_KEY is not set in the environment")

    run_date = datetime.now(timezone.utc).date()
    payload_text = fetch_breeds(api_key)
    count = validate(payload_text)

    out_dir = REPO_ROOT / "data" / "raw" / f"run_date={run_date.isoformat()}"
    out_dir.mkdir(parents=True, exist_ok=True)
    out_path = out_dir / "breeds.json"

    # Write to a temporary file in the same directory, then rename over the
    # target. os.replace is atomic on POSIX and Windows, so a crash mid-write
    # leaves the previous good file intact rather than a truncated one - the
    # script refuses partial data from the API, so it must not create partial
    # data itself. Same destination path each day, so this stays idempotent.
    tmp_path = out_dir / "breeds.json.tmp"
    tmp_path.write_text(payload_text, encoding="utf-8")
    os.replace(tmp_path, out_path)

    print(f"wrote {count} breeds to {out_path.relative_to(REPO_ROOT)}")


if __name__ == "__main__":
    main()
import json
import logging
import os
import time
import uuid
from urllib.parse import unquote_plus
from typing import Any, Dict, Iterable, Iterator, List, Optional, Sequence, Tuple


def _configure_logging() -> None:
    level_name = os.getenv("LOG_LEVEL", "INFO").upper()
    level = getattr(logging, level_name, logging.INFO)
    logging.getLogger().setLevel(level)
    logging.getLogger(__name__).setLevel(level)


_configure_logging()
logger = logging.getLogger(__name__)


def json_dumps(obj: Any) -> str:
    return json.dumps(obj, ensure_ascii=False, separators=(",", ":"), default=str)


def log(event: str, **fields: Any) -> None:
    payload = {"event": event, **fields}
    logger.info(json_dumps(payload))


def chunked(seq: Sequence[Any], n: int) -> Iterator[List[Any]]:
    for i in range(0, len(seq), n):
        yield list(seq[i : i + n])


def utc_epoch() -> int:
    return int(time.time())


def new_id(prefix: str = "") -> str:
    s = uuid.uuid4().hex
    return f"{prefix}{s}" if prefix else s


def env(name: str, default: Optional[str] = None) -> str:
    v = os.getenv(name, default)
    if v is None or v == "":
        raise RuntimeError(f"Missing env var: {name}")
    return v


def parse_s3_event_records(event: Dict[str, Any]) -> List[Tuple[str, str, str]]:
    records: List[Tuple[str, str, str]] = []
    for r in event.get("Records", []):
        s3 = r.get("s3", {})
        bucket = s3.get("bucket", {}).get("name")
        key = s3.get("object", {}).get("key")
        etag = s3.get("object", {}).get("eTag") or s3.get("object", {}).get("etag") or ""
        if not bucket or not key:
            continue
        key = unquote_plus(key)
        records.append((bucket, key, etag))
    return records


def iter_json_records(text: str) -> Iterable[Dict[str, Any]]:
    stripped = text.strip()
    if not stripped:
        return []

    if stripped.startswith("["):
        payload = json.loads(stripped)
        if not isinstance(payload, list):
            raise ValueError("Expected JSON array for bracketed payload")
        for obj in payload:
            if isinstance(obj, dict):
                yield obj
        return

    for line in text.splitlines():
        line = line.strip()
        if not line:
            continue
        obj = json.loads(line)
        if isinstance(obj, dict):
            yield obj

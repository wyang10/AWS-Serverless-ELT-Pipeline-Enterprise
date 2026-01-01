from __future__ import annotations

from datetime import datetime, timezone
from typing import Any, Dict, Iterable, List, Mapping


RECORD_TYPES = ("shipments", "tracking_events", "invoice_lines")


SCHEMAS: Mapping[str, List[str]] = {
    "shipments": ["record_type", "event_time", "shipment_id", "origin", "destination", "carrier", "weight_kg"],
    "tracking_events": ["record_type", "event_time", "shipment_id", "status", "city"],
    "invoice_lines": ["record_type", "event_time", "invoice_id", "sku", "quantity", "unit_price", "line_total"],
}


def normalize_record(record: Dict[str, Any]) -> Dict[str, Any]:
    record_type = record.get("record_type")
    if record_type not in SCHEMAS:
        raise ValueError(f"Unsupported record_type: {record_type}")

    out: Dict[str, Any] = {}
    for k in SCHEMAS[record_type]:
        out[k] = record.get(k)
    out["record_type"] = record_type

    event_time = out.get("event_time")
    if isinstance(event_time, str):
        out["event_time"] = _iso_to_iso_z(event_time)
    return out


def _iso_to_iso_z(s: str) -> str:
    if s.endswith("Z"):
        s = s[:-1] + "+00:00"
    dt = datetime.fromisoformat(s)
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


def to_pyarrow_schema(record_type: str):
    import pyarrow as pa  # type: ignore

    if record_type == "shipments":
        return pa.schema(
            [
                ("record_type", pa.string()),
                ("event_time", pa.string()),
                ("shipment_id", pa.string()),
                ("origin", pa.string()),
                ("destination", pa.string()),
                ("carrier", pa.string()),
                ("weight_kg", pa.float64()),
            ]
        )
    if record_type == "tracking_events":
        return pa.schema(
            [
                ("record_type", pa.string()),
                ("event_time", pa.string()),
                ("shipment_id", pa.string()),
                ("status", pa.string()),
                ("city", pa.string()),
            ]
        )
    if record_type == "invoice_lines":
        return pa.schema(
            [
                ("record_type", pa.string()),
                ("event_time", pa.string()),
                ("invoice_id", pa.string()),
                ("sku", pa.string()),
                ("quantity", pa.int64()),
                ("unit_price", pa.float64()),
                ("line_total", pa.float64()),
            ]
        )
    raise ValueError(f"Unsupported record_type: {record_type}")


def partition_dt(records: Iterable[Dict[str, Any]]) -> str:
    for r in records:
        s = r.get("event_time")
        if isinstance(s, str) and s:
            # 2025-01-01T...Z -> 2025-01-01
            return s[:10]
    return datetime.now(timezone.utc).date().isoformat()


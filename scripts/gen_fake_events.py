#!/usr/bin/env python3
"""
Generate fake events for the Bronze layer.

Examples:
- JSONL for S3 bronze:
  `python scripts/gen_fake_events.py --type shipments --count 100 --format jsonl --out /tmp/shipments.jsonl`
- Pretty JSON array:
  `python scripts/gen_fake_events.py --type shipments --count 100 --format json --out /tmp/shipments.json`
"""

import argparse
import json
import random
import sys
import uuid
from datetime import datetime, timedelta, timezone


def _dt_utc(days_back: int = 7) -> datetime:
    now = datetime.now(timezone.utc)
    return now - timedelta(seconds=random.randint(0, days_back * 24 * 3600))


def gen_shipments() -> dict:
    created_at = _dt_utc().isoformat()
    return {
        "record_type": "shipments",
        "event_time": created_at,
        "shipment_id": f"shp_{uuid.uuid4().hex[:12]}",
        "origin": random.choice(["SZX", "HKG", "LAX", "ORD"]),
        "destination": random.choice(["SEA", "JFK", "SFO", "DFW"]),
        "carrier": random.choice(["UPS", "DHL", "FEDEX"]),
        "weight_kg": round(random.random() * 30, 2),
    }


def gen_tracking_events() -> dict:
    event_time = _dt_utc().isoformat()
    return {
        "record_type": "tracking_events",
        "event_time": event_time,
        "shipment_id": f"shp_{uuid.uuid4().hex[:12]}",
        "status": random.choice(["CREATED", "IN_TRANSIT", "OUT_FOR_DELIVERY", "DELIVERED"]),
        "city": random.choice(["Shenzhen", "Hong Kong", "Los Angeles", "Chicago", "Seattle"]),
    }


def gen_invoice_lines() -> dict:
    event_time = _dt_utc().isoformat()
    qty = random.randint(1, 6)
    unit_price = round(random.random() * 50 + 3, 2)
    return {
        "record_type": "invoice_lines",
        "event_time": event_time,
        "invoice_id": f"inv_{uuid.uuid4().hex[:10]}",
        "sku": random.choice(["SKU-001", "SKU-002", "SKU-003"]),
        "quantity": qty,
        "unit_price": unit_price,
        "line_total": round(qty * unit_price, 2),
    }


GENERATORS = {
    "shipments": gen_shipments,
    "tracking_events": gen_tracking_events,
    "invoice_lines": gen_invoice_lines,
}


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate fake JSONL events for Bronze.")
    parser.add_argument("--type", choices=sorted(GENERATORS.keys()), required=True)
    parser.add_argument("--count", type=int, default=100)
    parser.add_argument("--format", choices=["jsonl", "json"], default="jsonl", help="Output format.")
    parser.add_argument("--out", default="-", help="Output path (default: stdout). Use '-' for stdout.")
    args = parser.parse_args()

    gen = GENERATORS[args.type]
    out_f = sys.stdout if args.out == "-" else open(args.out, "w", encoding="utf-8")
    try:
        if args.format == "jsonl":
            for _ in range(args.count):
                out_f.write(json.dumps(gen(), ensure_ascii=False) + "\n")
        else:
            payload = [gen() for _ in range(args.count)]
            out_f.write(json.dumps(payload, ensure_ascii=False, indent=2) + "\n")
    finally:
        if out_f is not sys.stdout:
            out_f.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

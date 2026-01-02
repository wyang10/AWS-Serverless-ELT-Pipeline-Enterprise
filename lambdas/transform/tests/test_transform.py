import pytest

import lambdas.transform.app as transform


def test_transform_returns_partial_failures_when_bad_json(monkeypatch):
    monkeypatch.setenv("SILVER_BUCKET", "out-bucket")
    monkeypatch.setenv("SILVER_PREFIX", "silver")

    # Avoid requiring pyarrow in unit tests; we only validate failure handling here.
    monkeypatch.setattr(transform, "_clients", lambda: None)
    monkeypatch.setattr(transform, "_s3_put_parquet", lambda *args, **kwargs: None)

    event = {
        "Records": [
            {"messageId": "m1", "body": '{"record_type":"shipments","event_time":"2025-01-01T00:00:00Z","shipment_id":"shp_1"}'},
            {"messageId": "m2", "body": "not-json"},
        ]
    }
    resp = transform.handler(event, context=type("C", (), {"aws_request_id": "r1", "function_name": "serverless-elt-transform"})())
    assert {"itemIdentifier": "m2"} in resp["batchItemFailures"]

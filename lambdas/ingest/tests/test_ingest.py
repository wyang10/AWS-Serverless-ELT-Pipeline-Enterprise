import pytest
from botocore.stub import ANY, Stubber

import lambdas.ingest.app as ingest


class _Body:
    def __init__(self, b: bytes):
        self._b = b

    def read(self):
        return self._b


def test_ingest_enqueues_and_marks_processed(monkeypatch):
    s3 = ingest.boto3.client("s3")
    sqs = ingest.boto3.client("sqs")
    ddb = ingest.boto3.client("dynamodb")

    s3_stubber = Stubber(s3)
    sqs_stubber = Stubber(sqs)
    ddb_stubber = Stubber(ddb)

    monkeypatch.setenv("QUEUE_URL", "https://sqs.example/123/q")
    monkeypatch.setenv("IDEMPOTENCY_TABLE", "tbl")
    monkeypatch.setenv("LOCK_SECONDS", "60")

    monkeypatch.setattr(ingest, "_clients", lambda: (s3, sqs, ddb))

    event = {
        "Records": [
            {
                "s3": {
                    "bucket": {"name": "bronze-bucket"},
                    "object": {"key": "bronze/shipments/a.jsonl", "eTag": "etag1"},
                }
            }
        ]
    }

    # Powertools idempotency: save_inprogress is a conditional PutItem (no need to validate params here).
    ddb_stubber.add_response("put_item", {}, None)

    s3_stubber.add_response(
        "get_object",
        {"Body": _Body(b'{"record_type":"shipments","event_time":"2025-01-01T00:00:00Z","shipment_id":"shp_1"}\n')},
        {"Bucket": "bronze-bucket", "Key": "bronze/shipments/a.jsonl"},
    )

    sqs_stubber.add_response(
        "send_message_batch",
        {"Successful": [{"Id": "0", "MessageId": "m1", "MD5OfMessageBody": "x"}], "Failed": []},
        {"QueueUrl": "https://sqs.example/123/q", "Entries": [{"Id": "0", "MessageBody": ANY}]},
    )

    # Powertools idempotency: save_success updates the record (no need to validate params).
    ddb_stubber.add_response("update_item", {}, None)

    with s3_stubber, sqs_stubber, ddb_stubber:
        resp = ingest.handler(
            event,
            context=type(
                "C",
                (),
                {
                    "aws_request_id": "r1",
                    "function_name": "serverless-elt-ingest",
                    "get_remaining_time_in_millis": lambda self: 10000,
                },
            )(),
        )

    assert resp["objects"] == 1
    assert resp["records"] == 1
    assert resp["enqueued"] == 1
    assert resp["skipped"] == 0


def test_ingest_skips_when_lock_not_acquired(monkeypatch):
    s3 = ingest.boto3.client("s3")
    sqs = ingest.boto3.client("sqs")
    ddb = ingest.boto3.client("dynamodb")

    monkeypatch.setenv("QUEUE_URL", "https://sqs.example/123/q")
    monkeypatch.setenv("IDEMPOTENCY_TABLE", "tbl")
    monkeypatch.setattr(ingest, "_clients", lambda: (s3, sqs, ddb))

    event = {
        "Records": [
            {
                "s3": {
                    "bucket": {"name": "bronze-bucket"},
                    "object": {"key": "bronze/shipments/a.jsonl", "eTag": "etag1"},
                }
            }
        ]
    }

    ddb_stubber = Stubber(ddb)
    # Simulate "already completed":
    # - Conditional put fails (no old item returned)
    # - Powertools idempotency falls back to GetItem and returns cached response
    ddb_stubber.add_client_error(
        "put_item",
        service_error_code="ConditionalCheckFailedException",
        service_message="condition failed",
        http_status_code=400,
        expected_params=None,
    )
    ddb_stubber.add_response(
        "get_item",
        {
            "Item": {
                "pk": {"S": "some-key"},
                "expires_at": {"N": "9999999999"},
                "status": {"S": "COMPLETED"},
                "data": {"S": "{\"records\":1,\"enqueued\":1,\"dropped\":0}"},
            }
        },
        None,
    )

    with ddb_stubber:
        resp = ingest.handler(
            event,
            context=type("C", (), {"function_name": "serverless-elt-ingest", "get_remaining_time_in_millis": lambda self: 10000})(),
        )

    assert resp["skipped"] == 1
    assert resp["records"] == 0

"""Triggered by new records on the vitals Kinesis stream (see
terraform/modules/streaming-alerts). Checks each vitals reading against
simple clinical danger thresholds and writes a row to the DynamoDB
active-alerts table for every reading that breaches one, so the operational
dashboard can surface it in near-real-time.

Thresholds here are deliberately simple (single-value range checks, not
trend-based) - good enough for a demo, not a real clinical decision engine.
"""

import base64
import json
import os
import time
import uuid
from decimal import Decimal

import boto3

_dynamodb = boto3.resource("dynamodb")

ALERT_TTL_SECONDS = 24 * 60 * 60  # active alerts expire after 24 hours

THRESHOLDS = {
    "heart_rate": {"min": 40, "max": 150},
    "spo2": {"min": 90, "max": None},
    "systolic_bp": {"min": 70, "max": 180},
    "temperature_c": {"min": 35.0, "max": 40.0},
}


def _breached_thresholds(vitals: dict) -> list:
    breached = []
    for field, limits in THRESHOLDS.items():
        value = vitals.get(field)
        if value is None:
            continue
        if limits["min"] is not None and value < limits["min"]:
            breached.append(f"{field} below {limits['min']} (was {value})")
        if limits["max"] is not None and value > limits["max"]:
            breached.append(f"{field} above {limits['max']} (was {value})")
    return breached


def handler(event, context):
    table = _dynamodb.Table(os.environ["ALERTS_TABLE_NAME"])
    alerts_written = 0

    for record in event["Records"]:
        payload = base64.b64decode(record["kinesis"]["data"])
        # DynamoDB's boto3 Table resource rejects native floats ("Float types
        # are not supported, use Decimal") - parse_float=Decimal converts
        # every numeric vitals reading up front instead of walking the dict
        # by hand before the put_item call below.
        vitals = json.loads(payload, parse_float=Decimal)

        breached = _breached_thresholds(vitals)
        if not breached:
            continue

        table.put_item(
            Item={
                "patient_id": vitals["patient_id"],
                "alert_id": str(uuid.uuid4()),
                "facility_id": vitals["facility_id"],
                "source_event_id": vitals["event_id"],
                "triggered_at": vitals["event_ts"],
                "reasons": breached,
                "vitals": vitals,
                "expires_at": int(time.time()) + ALERT_TTL_SECONDS,
            }
        )
        alerts_written += 1

    print(f"Processed {len(event['Records'])} vitals events, wrote {alerts_written} alerts")
    return {"records_processed": len(event["Records"]), "alerts_written": alerts_written}

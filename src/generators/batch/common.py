"""Shared reference data and helpers for the five batch generator Lambdas.

Every generator in this package imports from here so the synthetic facilities,
departments, patients, and staff stay consistent across sources (a claim and a
visit for the same patient_id should both look like they belong to the same
person). None of this is read from a database - it's just plain Python data,
since Phase 4 is where a real dimensional model shows up.
"""

import csv
import io
import os
from datetime import datetime, timezone

import boto3

FACILITIES = [
    {"facility_id": "FAC01", "facility_name": "Meridian General - Springfield"},
    {"facility_id": "FAC02", "facility_name": "Meridian North - Rivertown"},
    {"facility_id": "FAC03", "facility_name": "Meridian West - Lakeside"},
]

DEPARTMENTS = ["ER", "ICU", "Cardiology", "Pediatrics", "Orthopedics"]

PATIENT_IDS = [f"P{i:05d}" for i in range(1, 101)]

STAFF_IDS = [f"S{i:04d}" for i in range(1, 31)]

_s3 = boto3.client("s3")


def today_partition() -> str:
    """Today's date as a partition value, e.g. '2026-08-26'."""
    return datetime.now(timezone.utc).strftime("%Y-%m-%d")


def write_csv_to_s3(bucket: str, source: str, fieldnames: list, rows: list) -> str:
    """Write rows as a CSV file to <source>/dt=<today>/<source>-<ts>.csv.

    The bucket itself is the raw layer (see terraform/modules/s3-data-lake), so
    the key doesn't need its own "raw/" prefix. Returns the S3 key that was
    written, so the caller can log/return it.
    """
    buffer = io.StringIO()
    writer = csv.DictWriter(buffer, fieldnames=fieldnames)
    writer.writeheader()
    writer.writerows(rows)

    timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S")
    key = f"{source}/dt={today_partition()}/{source}-{timestamp}.csv"

    _s3.put_object(Bucket=bucket, Key=key, Body=buffer.getvalue().encode("utf-8"))
    return key


def raw_bucket_name() -> str:
    return os.environ["RAW_BUCKET_NAME"]

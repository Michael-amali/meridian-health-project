"""Generates a daily bed capacity snapshot per facility/department.

Simulates the RFP's "bed capacity snapshots" source, used later for
capacity-risk reporting on the operational dashboard.
"""

import random
from datetime import datetime, timezone

from common import DEPARTMENTS, FACILITIES, raw_bucket_name, write_csv_to_s3

FIELDNAMES = [
    "facility_id",
    "department",
    "total_beds",
    "occupied_beds",
    "snapshot_date",
]


def _random_capacity_row(facility_id: str, department: str, snapshot_date: str) -> dict:
    total_beds = random.randint(10, 60)
    occupied_beds = random.randint(0, total_beds)

    return {
        "facility_id": facility_id,
        "department": department,
        "total_beds": total_beds,
        "occupied_beds": occupied_beds,
        "snapshot_date": snapshot_date,
    }


def handler(event, context):
    snapshot_date = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    rows = [
        _random_capacity_row(facility["facility_id"], department, snapshot_date)
        for facility in FACILITIES
        for department in DEPARTMENTS
    ]

    key = write_csv_to_s3(raw_bucket_name(), "bed_capacity", FIELDNAMES, rows)
    print(f"Wrote {len(rows)} bed capacity records to {key}")
    return {"records_written": len(rows), "s3_key": key}

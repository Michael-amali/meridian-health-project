"""Generates today's shift schedule: one row per staff member.

Simulates the RFP's "staff schedules" source - a daily roster snapshot used
later for staffing-ratio and understaffing-risk reporting.
"""

import random
from datetime import datetime, timezone

from common import DEPARTMENTS, FACILITIES, STAFF_IDS, raw_bucket_name, write_csv_to_s3

ROLES = ["Nurse", "Physician", "Technician"]
SHIFTS = [
    {"shift_name": "Day", "shift_start": "07:00", "shift_end": "15:00"},
    {"shift_name": "Evening", "shift_start": "15:00", "shift_end": "23:00"},
    {"shift_name": "Night", "shift_start": "23:00", "shift_end": "07:00"},
]

FIELDNAMES = [
    "staff_id",
    "facility_id",
    "department",
    "role",
    "shift_date",
    "shift_name",
    "shift_start",
    "shift_end",
]


def _random_shift(staff_id: str, shift_date: str) -> dict:
    facility = random.choice(FACILITIES)
    shift = random.choice(SHIFTS)

    return {
        "staff_id": staff_id,
        "facility_id": facility["facility_id"],
        "department": random.choice(DEPARTMENTS),
        "role": random.choice(ROLES),
        "shift_date": shift_date,
        "shift_name": shift["shift_name"],
        "shift_start": shift["shift_start"],
        "shift_end": shift["shift_end"],
    }


def handler(event, context):
    shift_date = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    rows = [_random_shift(staff_id, shift_date) for staff_id in STAFF_IDS]

    key = write_csv_to_s3(raw_bucket_name(), "staff_schedules", FIELDNAMES, rows)
    print(f"Wrote {len(rows)} staff schedule records to {key}")
    return {"records_written": len(rows), "s3_key": key}

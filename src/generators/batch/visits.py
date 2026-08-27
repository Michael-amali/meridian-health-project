"""Generates a daily batch of patient visit/admission records.

Simulates the RFP's "visits/admissions" source: a snapshot of who was admitted
today, where, and by whom. Discharge time is left blank for a random subset to
represent patients still admitted at generation time.
"""

import random
import uuid
from datetime import datetime, timedelta, timezone

from common import DEPARTMENTS, FACILITIES, PATIENT_IDS, STAFF_IDS, raw_bucket_name, write_csv_to_s3

VISIT_TYPES = ["Emergency", "Inpatient", "Outpatient"]

FIELDNAMES = [
    "visit_id",
    "patient_id",
    "facility_id",
    "department",
    "visit_type",
    "attending_staff_id",
    "admission_ts",
    "discharge_ts",
]


def _random_visit(now: datetime) -> dict:
    admitted_hours_ago = random.randint(0, 23)
    admission_ts = now - timedelta(hours=admitted_hours_ago)

    # About 60% of today's admissions have already been discharged by now.
    discharge_ts = ""
    if random.random() < 0.6:
        discharge = admission_ts + timedelta(hours=random.randint(1, admitted_hours_ago + 1))
        discharge_ts = discharge.isoformat()

    facility = random.choice(FACILITIES)

    return {
        "visit_id": str(uuid.uuid4()),
        "patient_id": random.choice(PATIENT_IDS),
        "facility_id": facility["facility_id"],
        "department": random.choice(DEPARTMENTS),
        "visit_type": random.choice(VISIT_TYPES),
        "attending_staff_id": random.choice(STAFF_IDS),
        "admission_ts": admission_ts.isoformat(),
        "discharge_ts": discharge_ts,
    }


def handler(event, context):
    now = datetime.now(timezone.utc)
    visit_count = random.randint(20, 50)
    rows = [_random_visit(now) for _ in range(visit_count)]

    key = write_csv_to_s3(raw_bucket_name(), "visits", FIELDNAMES, rows)
    print(f"Wrote {len(rows)} visit records to {key}")
    return {"records_written": len(rows), "s3_key": key}

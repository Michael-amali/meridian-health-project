"""Generates a daily batch of billing/claims records.

Simulates the RFP's "billing/claims" source. Claims reference the same
patient/facility pool as visits.py so downstream referential-integrity checks
(Phase 3's Data Quality gate) have something real to validate against.
"""

import random
import uuid
from datetime import datetime, timezone

from common import FACILITIES, PATIENT_IDS, raw_bucket_name, write_csv_to_s3

PAYERS = ["Medicare", "Medicaid", "BlueCross", "Aetna", "UnitedHealth", "SelfPay"]
CLAIM_STATUSES = ["Submitted", "Paid", "Denied", "Pending"]

FIELDNAMES = [
    "claim_id",
    "patient_id",
    "facility_id",
    "payer",
    "claim_amount",
    "status",
    "service_date",
]


def _random_claim(service_date: str) -> dict:
    facility = random.choice(FACILITIES)

    return {
        "claim_id": str(uuid.uuid4()),
        "patient_id": random.choice(PATIENT_IDS),
        "facility_id": facility["facility_id"],
        "payer": random.choice(PAYERS),
        "claim_amount": round(random.uniform(75.0, 15000.0), 2),
        "status": random.choice(CLAIM_STATUSES),
        "service_date": service_date,
    }


def handler(event, context):
    service_date = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    claim_count = random.randint(15, 40)
    rows = [_random_claim(service_date) for _ in range(claim_count)]

    key = write_csv_to_s3(raw_bucket_name(), "billing_claims", FIELDNAMES, rows)
    print(f"Wrote {len(rows)} billing claim records to {key}")
    return {"records_written": len(rows), "s3_key": key}

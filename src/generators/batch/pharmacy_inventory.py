"""Generates a daily pharmacy inventory snapshot per facility.

Simulates the RFP's "pharmacy inventory" source - one row per drug per
facility, used later for stockout-risk reporting on the operational dashboard.
"""

import random
from datetime import datetime, timezone

from common import FACILITIES, raw_bucket_name, write_csv_to_s3

DRUGS = [
    "Acetaminophen", "Ibuprofen", "Amoxicillin", "Lisinopril", "Metformin",
    "Atorvastatin", "Albuterol", "Omeprazole", "Insulin Glargine", "Warfarin",
    "Morphine", "Epinephrine", "Furosemide", "Levothyroxine", "Amlodipine",
    "Metoprolol", "Prednisone", "Ciprofloxacin", "Heparin", "Ondansetron",
]

FIELDNAMES = [
    "facility_id",
    "drug_name",
    "current_stock",
    "reorder_threshold",
    "unit_cost",
    "snapshot_date",
]


def _random_stock_row(facility_id: str, drug_name: str, snapshot_date: str) -> dict:
    reorder_threshold = random.randint(20, 100)

    # Occasionally simulate a near-stockout so downstream stockout-risk
    # reporting (Phase 7) has something real to flag.
    if random.random() < 0.1:
        current_stock = random.randint(0, reorder_threshold - 1)
    else:
        current_stock = random.randint(reorder_threshold, reorder_threshold * 5)

    return {
        "facility_id": facility_id,
        "drug_name": drug_name,
        "current_stock": current_stock,
        "reorder_threshold": reorder_threshold,
        "unit_cost": round(random.uniform(0.10, 250.0), 2),
        "snapshot_date": snapshot_date,
    }


def handler(event, context):
    snapshot_date = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    rows = [
        _random_stock_row(facility["facility_id"], drug_name, snapshot_date)
        for facility in FACILITIES
        for drug_name in DRUGS
    ]

    key = write_csv_to_s3(raw_bucket_name(), "pharmacy_inventory", FIELDNAMES, rows)
    print(f"Wrote {len(rows)} pharmacy inventory records to {key}")
    return {"records_written": len(rows), "s3_key": key}

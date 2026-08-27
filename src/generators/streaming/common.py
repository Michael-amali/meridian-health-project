"""Shared synthetic value ranges for the streaming producer.

Deliberately reuses the same facility/patient ID pools as the batch
generators (duplicated here rather than imported, since the streaming and
batch Lambdas are packaged as separate, independent zips - see
terraform/modules/lambda-function).
"""

import random
import uuid
from datetime import datetime, timezone

FACILITY_IDS = ["FAC01", "FAC02", "FAC03"]
PATIENT_IDS = [f"P{i:05d}" for i in range(1, 101)]

PRESCRIPTION_DRUGS = [
    "Acetaminophen", "Ibuprofen", "Amoxicillin", "Lisinopril", "Metformin",
    "Atorvastatin", "Albuterol", "Omeprazole", "Insulin Glargine", "Warfarin",
]

# Normal human ranges. Alerting thresholds in the stream_alerting Lambda are
# wider than these, so a value outside a "normal" range isn't necessarily
# dangerous - it just makes the data look realistically noisy.
NORMAL_HEART_RATE = (60, 100)
NORMAL_SPO2 = (95, 100)
NORMAL_SYSTOLIC_BP = (100, 130)
NORMAL_DIASTOLIC_BP = (60, 85)
NORMAL_TEMPERATURE_C = (36.1, 37.5)

# Dangerous ranges, used for the ~5% of readings deliberately generated
# out-of-range so the alerting Lambda has something real to catch.
DANGEROUS_HEART_RATE = [(25, 39), (151, 200)]
DANGEROUS_SPO2 = [(70, 89)]
DANGEROUS_SYSTOLIC_BP = [(50, 69), (181, 220)]
DANGEROUS_TEMPERATURE_C = [(34.0, 34.9), (40.1, 42.0)]

DANGEROUS_READING_CHANCE = 0.05


def _value_in_ranges(ranges: list) -> float:
    low, high = random.choice(ranges)
    return round(random.uniform(low, high), 1)


def generate_vitals_event() -> dict:
    is_dangerous = random.random() < DANGEROUS_READING_CHANCE

    if is_dangerous:
        heart_rate = _value_in_ranges(DANGEROUS_HEART_RATE)
        spo2 = _value_in_ranges(DANGEROUS_SPO2)
        systolic_bp = _value_in_ranges(DANGEROUS_SYSTOLIC_BP)
        temperature_c = _value_in_ranges(DANGEROUS_TEMPERATURE_C)
    else:
        heart_rate = round(random.uniform(*NORMAL_HEART_RATE), 1)
        spo2 = round(random.uniform(*NORMAL_SPO2), 1)
        systolic_bp = round(random.uniform(*NORMAL_SYSTOLIC_BP), 1)
        temperature_c = round(random.uniform(*NORMAL_TEMPERATURE_C), 1)

    return {
        "event_id": str(uuid.uuid4()),
        "patient_id": random.choice(PATIENT_IDS),
        "facility_id": random.choice(FACILITY_IDS),
        "heart_rate": heart_rate,
        "spo2": spo2,
        "systolic_bp": systolic_bp,
        "diastolic_bp": round(random.uniform(*NORMAL_DIASTOLIC_BP), 1),
        "temperature_c": temperature_c,
        "event_ts": datetime.now(timezone.utc).isoformat(),
    }


def generate_prescription_event() -> dict:
    return {
        "event_id": str(uuid.uuid4()),
        "patient_id": random.choice(PATIENT_IDS),
        "facility_id": random.choice(FACILITY_IDS),
        "drug_name": random.choice(PRESCRIPTION_DRUGS),
        "dosage_mg": random.choice([5, 10, 25, 50, 100, 250, 500]),
        "event_ts": datetime.now(timezone.utc).isoformat(),
    }

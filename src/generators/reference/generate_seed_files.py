"""One-time generator for the Phase 4 patient/staff reference seed CSVs.

Run manually (`python generate_seed_files.py`) whenever the seed data needs
regenerating - this is NOT deployed as a Lambda like the Phase 2 batch
generators, since patient/staff master data doesn't change day to day the way
visits or bed capacity do. The output is committed to the repo as the actual
seed data Terraform uploads (see terraform/modules/bronze-to-silver/main.tf),
so this script's only job is reproducibility of that seed, not runtime
execution.

random.seed(...) makes re-running this script produce byte-identical output.
Patient/staff ID ranges match the pools already used everywhere else (see
src/generators/batch/common.py's PATIENT_IDS/STAFF_IDS).
"""

import csv
import random
from datetime import date, timedelta
from pathlib import Path

random.seed(42)

FIRST_NAMES = [
    "James", "Mary", "Robert", "Patricia", "John", "Jennifer", "Michael", "Linda",
    "David", "Elizabeth", "William", "Barbara", "Richard", "Susan", "Joseph", "Jessica",
    "Thomas", "Sarah", "Charles", "Karen", "Christopher", "Nancy", "Daniel", "Lisa",
    "Matthew", "Betty", "Anthony", "Margaret", "Mark", "Sandra", "Donald", "Ashley",
    "Steven", "Kimberly", "Paul", "Emily", "Andrew", "Donna", "Joshua", "Michelle",
    "Kenneth", "Carol", "Kevin", "Amanda", "Brian", "Melissa", "George", "Deborah",
    "Timothy", "Stephanie",
]

LAST_NAMES = [
    "Smith", "Johnson", "Williams", "Brown", "Jones", "Garcia", "Miller", "Davis",
    "Rodriguez", "Martinez", "Hernandez", "Lopez", "Gonzalez", "Wilson", "Anderson",
    "Thomas", "Taylor", "Moore", "Jackson", "Martin", "Lee", "Perez", "Thompson", "White",
    "Harris", "Sanchez", "Clark", "Ramirez", "Lewis", "Robinson", "Walker", "Young",
    "Allen", "King", "Wright", "Scott", "Torres", "Nguyen", "Hill", "Flores", "Green",
    "Adams", "Nelson", "Baker", "Hall", "Rivera", "Campbell", "Mitchell", "Carter", "Roberts",
]

SEED_DATA_DIR = Path(__file__).resolve().parents[3] / "terraform/modules/bronze-to-silver/seed-data"


def _random_name() -> str:
    return f"{random.choice(FIRST_NAMES)} {random.choice(LAST_NAMES)}"


def _random_dob(min_age_years: int, max_age_years: int) -> str:
    # A fixed reference date (rather than datetime.now()) keeps this script's
    # output byte-identical across re-runs, matching the module docstring.
    reference_date = date(2026, 1, 1)
    age_days = random.randint(min_age_years * 365, max_age_years * 365)
    return (reference_date - timedelta(days=age_days)).isoformat()


def _random_phone() -> str:
    return f"555-{random.randint(1000, 9999)}"


def _write_csv(path: Path, fieldnames: list, rows: list) -> None:
    with open(path, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def _generate_patients() -> tuple:
    fieldnames = ["patient_id", "full_name", "date_of_birth", "phone", "government_id"]
    rows = [
        {
            "patient_id": f"P{i:05d}",
            "full_name": _random_name(),
            "date_of_birth": _random_dob(0, 90),
            "phone": _random_phone(),
            "government_id": f"GID-{i:05d}",
        }
        for i in range(1, 101)
    ]
    return fieldnames, rows


def _generate_staff() -> tuple:
    fieldnames = ["staff_id", "full_name", "date_of_birth", "phone", "government_id"]
    rows = [
        {
            "staff_id": f"S{i:04d}",
            "full_name": _random_name(),
            "date_of_birth": _random_dob(23, 65),
            "phone": _random_phone(),
            "government_id": f"GID-S{i:04d}",
        }
        for i in range(1, 31)
    ]
    return fieldnames, rows


if __name__ == "__main__":
    SEED_DATA_DIR.mkdir(parents=True, exist_ok=True)

    patient_fieldnames, patient_rows = _generate_patients()
    _write_csv(SEED_DATA_DIR / "patients.csv", patient_fieldnames, patient_rows)

    staff_fieldnames, staff_rows = _generate_staff()
    _write_csv(SEED_DATA_DIR / "staff.csv", staff_fieldnames, staff_rows)

    print(f"Wrote {len(patient_rows)} patients and {len(staff_rows)} staff to {SEED_DATA_DIR}")

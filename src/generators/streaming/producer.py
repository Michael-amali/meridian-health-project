"""Runs every minute (see terraform/modules/streaming-producer) and pushes a
small batch of synthetic vitals + prescription-issuance events onto their
respective Kinesis streams.
"""

import json
import os
import random

import boto3

from common import generate_prescription_event, generate_vitals_event

_kinesis = boto3.client("kinesis")


def _put_records(stream_name: str, events: list):
    # The trailing newline is not cosmetic. Kinesis Data Firehose concatenates
    # record payloads back to back with nothing between them, so without it
    # every delivered S3 object is one long line of "}{"-joined JSON. Spark
    # and Athena both read JSON a line at a time, so they would silently keep
    # only the first event in each object and drop the rest - no error, just
    # missing data. Adding the delimiter here costs nothing; the alternative
    # is a Firehose transformation Lambda that does the same thing per record.
    records = [
        {
            "Data": (json.dumps(event) + "\n").encode("utf-8"),
            "PartitionKey": event["patient_id"],
        }
        for event in events
    ]
    response = _kinesis.put_records(StreamName=stream_name, Records=records)

    if response["FailedRecordCount"] > 0:
        print(f"{response['FailedRecordCount']} records failed to put to {stream_name}")

    return len(records) - response["FailedRecordCount"]


def handler(event, context):
    vitals_stream = os.environ["VITALS_STREAM_NAME"]
    prescriptions_stream = os.environ["PRESCRIPTIONS_STREAM_NAME"]

    vitals_events = [generate_vitals_event() for _ in range(random.randint(5, 15))]
    prescription_events = [generate_prescription_event() for _ in range(random.randint(1, 5))]

    vitals_sent = _put_records(vitals_stream, vitals_events)
    prescriptions_sent = _put_records(prescriptions_stream, prescription_events)

    print(f"Sent {vitals_sent} vitals events, {prescriptions_sent} prescription events")
    return {"vitals_sent": vitals_sent, "prescriptions_sent": prescriptions_sent}

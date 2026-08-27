# Meridian Health Network — Architecture

End-to-end AWS analytics platform architecture, organized by delivery phase (see the
9-phase plan). Each subgraph below is tagged with the phase that builds it.

## System architecture (by phase)

```mermaid
flowchart LR
    subgraph P2["Phase 2 — Ingestion"]
        direction TB
        BatchGen["Batch generators\n(visits, staff, billing,\npharmacy, bed capacity)"]
        StreamGen["Streaming producer\n(vitals, prescriptions)\nEventBridge ~1/min"]
        Kinesis["Kinesis Data Streams\n(on-demand)"]
        Firehose["Kinesis Firehose\n-> Parquet"]
        AlertLambda["Lambda: stream_alerting\n(flags critical vitals)"]
        DynamoAlerts[("DynamoDB\nactive_alerts")]

        StreamGen --> Kinesis
        Kinesis --> Firehose
        Kinesis --> AlertLambda
        AlertLambda --> DynamoAlerts
    end

    subgraph P1["Phase 1 — Foundations"]
        direction TB
        S3Raw[("S3 raw/")]
        KMS["KMS CMK\n(encryption at rest)"]
        IAMBase["Baseline IAM roles\n(Glue, Lambda)"]
    end

    BatchGen --> S3Raw
    Firehose --> S3Raw

    subgraph P3["Phase 3 — Bronze to Silver"]
        direction TB
        Crawler1["Glue Crawler\n(raw)"]
        CleanseJobs["Glue Jobs (PySpark)\nper-source cleansing"]
        DQ["Glue Data Quality\n(DQDL rules gate)"]
        S3Cleansed[("S3 cleansed/\nParquet, PII-tagged")]
        Catalog["Glue Data Catalog"]
        Athena["Athena\n(ad-hoc query)"]

        S3Raw --> Crawler1 --> Catalog
        S3Raw --> CleanseJobs --> DQ --> S3Cleansed
        S3Cleansed --> Catalog --> Athena
    end

    subgraph P4["Phase 4 — Silver to Gold"]
        direction TB
        CurateJobs["Glue Jobs\njoin/aggregate to\nstar schema"]
        S3Curated[("S3 curated/\nfact_* / dim_*")]
        LakeFormation["Lake Formation\ntag-based access +\nPII masking"]

        S3Cleansed --> CurateJobs --> S3Curated
        Catalog --> LakeFormation
        LakeFormation -.governs.-> S3Curated
    end

    subgraph P6["Phase 6 — Warehouse"]
        direction TB
        Redshift[("Redshift Serverless\n(namespace + workgroup)\nRLS by facility")]
        S3Curated --> Redshift
    end

    subgraph P5["Phase 5 — Orchestration & Monitoring"]
        direction TB
        StepFn["Step Functions\n(batch-daily, batch-weekly,\nstreaming-curation)"]
        EventBridgeSched["EventBridge Scheduler"]
        CloudWatch["CloudWatch\ndashboards + alarms"]
        SNS["SNS -> email"]

        EventBridgeSched --> StepFn
        StepFn -.orchestrates.-> Crawler1
        StepFn -.orchestrates.-> CleanseJobs
        StepFn -.orchestrates.-> DQ
        StepFn -.orchestrates.-> CurateJobs
        StepFn -.orchestrates.-> Redshift
        StepFn --> CloudWatch --> SNS
    end

    subgraph P7["Phase 7 — BI"]
        direction TB
        SPICE["QuickSight\nSPICE datasets"]
        ExecDash["Executive dashboard\n(network + per-facility trends)"]
        OpsDash["Operational/Clinical dashboard\n(RLS: facility manager scope)"]

        Redshift --> SPICE
        DynamoAlerts -.near-real-time.-> OpsDash
        SPICE --> ExecDash
        SPICE --> OpsDash
    end

    subgraph P8["Phase 8 — Promotion & CI/CD"]
        direction TB
        Terraform["Terraform modules\n(dev / test / prod)"]
        GHA["GitHub Actions\nplan on PR, apply on merge"]
        GHA --> Terraform
    end

    KMS -.encrypts.-> S3Raw
    KMS -.encrypts.-> S3Cleansed
    KMS -.encrypts.-> S3Curated
    KMS -.encrypts.-> Redshift
    IAMBase -.least-privilege.-> CleanseJobs
    IAMBase -.least-privilege.-> AlertLambda
```

## Phase delivery roadmap

```mermaid
flowchart TD
    P1["1. Foundations\nTerraform backend, S3 buckets, KMS, IAM\n**DONE**"]
    P2["2. Ingestion\nBatch generators + Kinesis streaming + alerting\n**IN PROGRESS**"]
    P3["3. Bronze -> Silver\nCrawlers, cleansing jobs, Data Quality gate"]
    P4["4. Silver -> Gold\nDimensional model, Lake Formation governance"]
    P5["5. Orchestration\nStep Functions, EventBridge, CloudWatch/SNS"]
    P6["6. Warehouse\nRedshift Serverless, star schema, RLS"]
    P7["7. BI Dashboards\nQuickSight Executive + Operational/Clinical"]
    P8["8. Promotion & CI/CD\ndev -> test -> prod via GitHub Actions"]
    P9["9. Documentation\nArchitecture, data model, governance, runbook"]

    P1 --> P2 --> P3 --> P4 --> P5 --> P6 --> P7 --> P8 --> P9
```

## Notes

- Each phase is independently shippable and verified against `dev` before moving on
  (Terraform `plan`/`apply`, manual pipeline run, inspection of actual output — not
  just exit codes).
- Encryption (KMS, TLS in transit) and least-privilege IAM apply across every phase,
  not just Phase 1 — shown as cross-cutting links above.
- See the RFP/plan source for full per-phase acceptance criteria.

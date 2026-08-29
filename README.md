# Meridian Health Network — Patient Care & Hospital Operations Analytics Platform

An end-to-end AWS data platform (Terraform, S3, Glue, Kinesis, Redshift Serverless,
Step Functions, Lake Formation, QuickSight) built against the CIO's RFP for a governed
lakehouse serving executive and operational/clinical dashboards. Built with synthetic
data — see `docs/architecture.md` (added in a later phase) for why.

Full architecture and the phased build plan live in the plan doc used to build this
repo; see `docs/` for living documentation as each phase lands.

## Status

**Phase 1 (Foundations) — complete.** Terraform state backend, KMS key, S3 data lake
buckets (raw/cleansed/curated/scripts/logs), and baseline IAM service roles are live in
the `dev` environment.

**Phase 2 (Synthetic Data Generators & Raw Ingestion) — complete.** Five daily batch
generators (visits, staff schedules, billing claims, pharmacy inventory, bed capacity)
write CSV to `raw/<source>/dt=.../`. A 1-minute streaming producer pushes synthetic
vitals + prescription-issuance events onto two on-demand Kinesis streams, delivered to
`raw/vitals/` and `raw/prescriptions/` as JSON via Firehose. A Kinesis-triggered alerting
Lambda flags dangerous vitals readings into a `meridian-active-alerts-dev` DynamoDB
table (24h TTL). All verified end-to-end in `dev`: manual invokes landed real objects in
S3, and the streaming path produced real active alerts.

**Phase 3 (Bronze → Silver) — complete.** Glue Crawlers + 7 per-source cleansing Glue
jobs promote raw data to partitioned cleansed Parquet, gated by a Glue Data Quality
ruleset per source: rows that fail any rule are quarantined instead of blocking the
whole run. Rule-level outcomes land in a queryable `dq_results` table; row-level
outcomes drive quarantine. All 7 sources verified against real AWS, including a
deliberately bad record to confirm quarantine actually catches it.

**Phase 4 (Silver → Gold + Lake Formation governance) — complete.** Two new static
reference sources (`patients`, `staff` - fake PII seed data) flow through the same
Phase 3 cleansing machinery. 13 curated Glue jobs build a star schema (7 dims + 6 facts)
in `curated/`, full-refresh each run. Lake Formation governs the curated layer only:
`dim_patient`/`dim_staff`'s PII columns (name, DOB, phone, government ID) are excluded
from two demo IAM roles (`meridian-analyst-role-dev`, `meridian-executive-role-dev`) via
column-level grants, verified end-to-end by actually assuming one of those roles and
confirming the PII columns are absent from an Athena query while the rest of the row is
visible. **Note:** this phase changed an account-wide Lake Formation setting
(`create_database_default_permissions`/`create_table_default_permissions` set to empty)
- any new Glue database created anywhere in this account from now on needs explicit
Lake Formation grants; it no longer gets implicit IAM-passthrough access.

**Phase 5 (Orchestration) - complete.** Two Step Functions state machines built from
one reusable module tie the pipeline together: `batch-daily` (5 cleanse jobs -> 7 curate
jobs -> Redshift load -> SNS) on an 08:00 UTC EventBridge schedule, and
`streaming-curation` (vitals/prescriptions) every 30 minutes. Retry/catch on every Glue
step, an SNS alerts topic, 3 CloudWatch alarms (pipeline failure, Kinesis iterator age,
DQ quarantine volume) and a pipeline dashboard. Verified by killing a Glue job mid-run
and confirming Step Functions retried and recovered with no manual intervention.

**Phase 6 (Warehouse) - complete.** A Redshift Serverless namespace/workgroup in its own
private VPC (3 AZs, no NAT - an S3 gateway endpoint covers COPY), the 13-table star
schema with deliberate dist/sort keys, and facility-scoped native row-level security
with a demo database user per facility. Both Phase 5 pipelines gained a Redshift load
stage, so the warehouse stays current. Verified with real per-facility queries proving
RLS filters rather than merely existing, and by re-running the pipeline to confirm
TRUNCATE + COPY never double-counts.

**Phase 7 (BI dashboards) - complete.** QuickSight reaches the private Redshift
workgroup over a VPC connection, connecting as a dedicated read-only database user
rather than the admin. Six SPICE datasets (custom SQL over the star schema) feed an
**Executive** dashboard - visits, length of stay, 30-day readmission rate, claim value
and denial rate by payer, bed occupancy trend, staffing ratio - and an
**Operational & Clinical** dashboard - occupancy and capacity risk by department, staff
by shift, stockout worklist, critical vitals alerts per hour, and a facility drop-down
that moves every visual at once. Per-viewer facility scoping is enforced by QuickSight's
own row-level security, driven by a `quicksight_user_facility_map` table in Redshift:
the dashboards share one database connection, so Phase 6's native Redshift RLS cannot
tell one viewer from another. Set a user's `facility_id` to `null` in
`var.quicksight_facility_access` for the unrestricted executive view.

**Bug found and fixed during Phase 7 verification:** the streaming producer was sending
Kinesis records with no trailing newline. Firehose concatenates record payloads verbatim,
so every delivered S3 object was one long `}{`-joined line, and both Spark and Athena
silently kept only the first event per object - roughly 90% of all vitals and
prescription events had been discarded since Phase 2, with no error anywhere. Fixed in
`src/generators/streaming/producer.py`; re-verified end to end (34 events in one object
instead of 1, and real critical-vitals alerts now reaching `fact_vitals_alert`).

All of the above is live in `dev` only - `test`/`prod` have the same Terraform but are
not yet applied (Phase 8).

## Repo layout

```
terraform/
  bootstrap/        # one-time: creates the Terraform state S3 bucket + DynamoDB lock table
  modules/          # reusable building blocks (kms, s3-data-lake, iam-baseline, ...)
  environments/     # dev/, test/, prod/ - each wires the modules together for that env
src/
  generators/       # synthetic batch + streaming data producers (Phase 2+)
  glue_jobs/        # bronze_to_silver/, silver_to_gold/ PySpark jobs (Phase 3+)
  lambdas/          # stream_alerting, redshift_loader (Phase 2+)
  dq/               # Glue Data Quality rule definitions (Phase 3+)
docs/               # architecture, data model, governance, runbook (Phase 9)
```

## Working with Terraform

Each environment under `terraform/environments/<env>` is a self-contained root module
with its own remote state (S3 backend, key `<env>/terraform.tfstate`, shared state
bucket/lock table created once by `terraform/bootstrap`).

```bash
cd terraform/environments/dev
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

Never run `terraform apply` without reviewing the plan first, especially against `prod`.

## Conventions

- Every resource name is prefixed `meridian-` and suffixed with the environment
  (`-dev`, `-test`, `-prod`); S3 bucket names additionally suffix the AWS account ID
  since bucket names must be globally unique.
- Tagging (`Project`, `Environment`, `ManagedBy`) is applied automatically via each
  environment's provider `default_tags` block — you don't need to tag resources by hand.
- Code is written to be read by a junior engineer first, clever second: prefer explicit,
  slightly repetitive resources over abstractions that hide what's actually happening.

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
S3, and the streaming path produced real active alerts. Live in `dev` only - `test`/
`prod` have the same Terraform but are not yet applied (Phase 8).

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

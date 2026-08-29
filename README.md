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

**Phase 8 (Test/Prod promotion + CI/CD) — complete.** `dev`, `test` and `prod` now run
byte-for-byte the same Terraform; the only per-environment files are `backend.tf` (state
key) and `terraform.tfvars` (values). GitHub Actions plans all three environments on every
pull request using a read-only AWS role, and on merge to `master` applies dev → test →
prod in order, with `test` and `prod` gated behind GitHub Environment approvals. See
[Environments](#environments) and [CI/CD](#cicd-github-actions) below.

Standing `test` up from nothing surfaced two latent bugs that five phases of incremental
work on `dev` had hidden, both now fixed:

- The vitals alerting role was missing `kinesis:DescribeStreamSummary` and
  `kinesis:ListStreams`. Lambda checks for those when an event source mapping is
  *created*, not when it polls, so `dev`'s existing mapping kept working and only a fresh
  environment failed.
- Nothing made the QuickSight module wait for the Redshift star-schema tables to exist, so
  its `GRANT SELECT` setup ran first and failed with `relation "dim_facility" does not
  exist`. `dev` never hit it because the tables were already there from Phase 6 by the time
  Phase 7 was written.

## Environments

`dev`, `test` and `prod` are three root modules under `terraform/environments/`. Their
`main.tf`, `variables.tf`, `outputs.tf` and `providers.tf` are **identical files** - if you
change one, copy it to the other two. Only two files differ per environment:

| File | What differs |
|---|---|
| `backend.tf` | the state key (`dev/`, `test/`, `prod/terraform.tfstate`) |
| `terraform.tfvars` | the values below |

That is the whole point of the promotion story: if the environments differed in code,
"we tested this in dev before it reached prod" would not mean much, because the thing
running in prod would not be the thing that was tested. If an environment needs to behave
differently, add a variable and set it in that environment's tfvars - do not fork the code.

### Cost knobs

Every environment creates every resource. What differs is whether AWS runs things
unattended:

| Variable | dev | test | prod | What it gates |
|---|---|---|---|---|
| `batch_schedules_enabled` | `true` | `false` | `false` | the 5 generator Lambdas (06:00-06:20 UTC) + the batch-daily pipeline (08:00 UTC) |
| `streaming_enabled` | `false` | `false` | `false` | the Kinesis producer, the vitals consumer, and the 30-minute streaming-curation pipeline |
| `quicksight_refresh_schedules_enabled` | `true` | `false` | `false` | SPICE refresh schedules |
| `redshift_base_capacity` | `8` | `8` | `8` | Redshift Serverless RPUs (8 is the AWS minimum) |
| `manage_lake_formation_account_settings` | `true` | `false` | `false` | see below |

Nothing here deletes a resource. Every Lambda, Glue job, state machine and dataset still
exists and can be run by hand:

```bash
aws lambda invoke --function-name meridian-gen-visits-test /dev/null
aws stepfunctions start-execution --state-machine-arn <batch_daily_state_machine_arn>
```

### The one account-wide resource

`aws_lakeformation_data_lake_settings` is a **singleton per AWS account**, and this project
runs all three environments in one account. Exactly one environment may own it - `dev`
does, via `manage_lake_formation_account_settings = true`.

Do not turn that on for a second environment. Two owners means whichever applied last
silently wins, and `terraform destroy` on a non-owning environment would delete the shared
object and re-enable the account-wide `IAMAllowedPrincipals` grant - which is precisely what
Phase 4's column-level PII masking depends on being switched off.

## Standing up a new environment from scratch

A brand-new environment cannot be applied in one shot. Two circular dependencies get in
the way, both of which fail in ways that look like something else:

1. **Lake Formation's named-table grants** need the curated tables to exist in the Glue
   Catalog - and 11 of the 13 are discovered by a crawler, so they only appear once data
   has actually flowed through.
2. **The crawler itself** needs a Lake Formation grant before it can write to the curated
   database. Because the account-wide setting strips the legacy `IAMAllowedPrincipals`
   grant from every newly created database, a fresh curated database gives the Glue role
   nothing at all, and the crawler fails with `Insufficient Lake Formation permission(s):
   Required Describe on meridian_curated_<env>`. The grant that fixes this lives in the
   same module as the named-table grants from (1), so it has to be applied separately,
   ahead of them.

The full sequence, in order:

```bash
cd terraform/environments/<env>
terraform init

# 1. Everything except the grants. Name EVERY module explicitly - do not rely
#    on -target pulling modules in as dependencies. It only pulls in resources
#    something targeted actually references, so naming a subset silently skips
#    anything nothing points at: the Firehose delivery streams, the IAM inline
#    policies, bucket versioning/lifecycle. You get a stack that applies
#    cleanly and is quietly incomplete.
terraform apply   -target=module.kms                  -target=module.s3_data_lake   -target=module.kinesis_streaming    -target=module.dynamodb_alerts   -target=module.iam_baseline         -target=module.batch_generators   -target=module.streaming_producer   -target=module.streaming_alerts   -target=module.bronze_to_silver     -target=module.lake_formation_bootstrap   -target=module.silver_to_gold       -target=module.sns_alerts   -target=module.redshift_warehouse   -target=module.batch_daily_pipeline   -target=module.streaming_curation_pipeline   -target=module.monitoring           -target=module.quicksight_bi

# 2. The Glue service role's Lake Formation grants, so the crawler can work.
#    These are database- and wildcard-scoped, so unlike the demo grants below
#    they do NOT need any table to exist yet.
terraform apply   -target=module.lake_formation_grants.aws_lakeformation_permissions.glue_service_database   -target=module.lake_formation_grants.aws_lakeformation_permissions.glue_service_tables   -target=module.lake_formation_grants.aws_lakeformation_permissions.glue_service_data_location

# 3. Seed one day of data - see "Seeding a new environment" below.
# 4. Run the curated crawler (it is the last command in that section).

# 5. Now the named-table grants apply, and this is a normal full apply.
terraform apply

# 6. Load the warehouse - see "Loading Redshift after seeding" below.
```

After this, ordinary changes are a single `terraform apply`; the staging above is a
one-time cost per environment.

### Seeding a new environment

```bash
ENV=test
RUN_DATE=$(date -u +%Y-%m-%d)

# 5 batch generators -> raw/<source>/dt=<today>/
for src in visits staff_schedules billing_claims pharmacy_inventory bed_capacity; do
  aws lambda invoke --function-name "meridian-gen-${src}-${ENV}" /dev/null
done

# Streaming producer -> Kinesis -> Firehose -> raw/{vitals,prescriptions}/dt=<today>/
# Firehose buffers for 60s, so wait before starting the cleanse jobs for those two.
for i in 1 2 3; do
  aws lambda invoke --function-name "meridian-streaming-producer-${ENV}" /dev/null
done

# Cleanse. Three things bite here:
#   * RUN_DATE must be passed. The jobs default it to YESTERDAY (so a scheduled
#     run gets a fully-landed partition), but the generators just wrote TODAY.
#     Omit it and every job SUCCEEDS having processed nothing at all - there is
#     no error to notice.
#   * patients/staff are static reference data at a FIXED dt=2025-01-01, not a
#     daily partition, so they need a different RUN_DATE from the other seven.
#   * --arguments needs JSON. The shorthand form breaks because Glue argument
#     names start with `--`, which the AWS CLI parses as another option.
for src in visits staff_schedules billing_claims pharmacy_inventory bed_capacity vitals prescriptions; do
  aws glue start-job-run --job-name "meridian-cleanse-${src}-${ENV}"     --arguments "{\"--RUN_DATE\":\"${RUN_DATE}\"}"
done
for src in patients staff; do
  aws glue start-job-run --job-name "meridian-cleanse-${src}-${ENV}"     --arguments '{"--RUN_DATE":"2025-01-01"}'
done

# Curate (no RUN_DATE - every curated table is a full refresh), then crawl.
for t in dim_date dim_department dim_drug dim_facility dim_patient dim_payer dim_staff          fact_bed_occupancy fact_claim fact_patient_visit fact_pharmacy_inventory          fact_staffing fact_vitals_alert; do
  aws glue start-job-run --job-name "meridian-curate-${t}-${ENV}"
done
aws glue start-crawler --name "meridian-curated-crawler-${ENV}"
```

Wait for each stage to finish before starting the next - the cleanse jobs feed the curate
jobs, and the crawler needs the curated Parquet to exist before it can create the tables
the Lake Formation grants are waiting on.

### Loading Redshift after seeding

`modules/redshift-warehouse` runs a one-time `TRUNCATE` + `COPY` per table at apply time.
On a brand-new environment that runs in step 1, when the curated bucket is still empty, so
it loads nothing - and it is a fire-once resource that will not run again. In `dev` this
self-corrects, because the scheduled pipelines do their own `TRUNCATE` + `COPY` every day.
In an idle environment with the schedules off, nothing ever fixes it, and the warehouse and
dashboards sit empty while every `terraform plan` reports no changes.

So after seeding, load it by hand once:

```bash
ENV=test
ROLE=$(aws iam list-roles   --query "Roles[?contains(RoleName,'redshift') && contains(RoleName,'${ENV}')].Arn" --output text)
WG=$(terraform output -raw redshift_workgroup_name)
DB=$(terraform output -raw redshift_database_name)
SEC=$(terraform output -raw redshift_admin_secret_arn)

SQLS=""
for t in dim_date dim_department dim_drug dim_facility dim_patient dim_payer dim_staff          fact_bed_occupancy fact_claim fact_patient_visit fact_pharmacy_inventory          fact_staffing fact_vitals_alert; do
  SQLS="$SQLS \"TRUNCATE TABLE $t\" \"COPY $t FROM 's3://meridian-curated-${ENV}-myk/$t/' IAM_ROLE '$ROLE' FORMAT AS PARQUET\""
done
eval aws redshift-data batch-execute-statement   --workgroup-name "$WG" --database "$DB" --secret-arn "$SEC" --sqls $SQLS
```

## CI/CD (GitHub Actions)

Two workflows, and no AWS access keys anywhere - GitHub mints a short-lived OIDC token per
run and AWS is configured to trust that issuer (`terraform/github-oidc/`).

**`terraform plan`** runs on every pull request. It checks formatting, then plans all three
environments in parallel and posts each plan as a PR comment. It assumes
`meridian-github-plan`, which holds `ReadOnlyAccess` and can change nothing. All three are
planned on purpose: the environments share one set of `.tf` files, so a change written with
only dev in mind shows up as an unexpected diff against test or prod *before* it merges.

**`terraform apply`** runs on merge to `master`, applying **dev → test → prod** in order and
stopping at the first failure. Each job declares a GitHub Environment, and that is the gate:

- GitHub will not start a job whose environment has required reviewers until a human approves.
- The AWS role that job assumes trusts **only** that environment's OIDC subject claim
  (`repo:<owner>/<repo>:environment:prod`). GitHub mints that claim, not the workflow, so
  editing the workflow file cannot get a job into prod early - the role will not let it in.

That is what "a merge never reaches prod on its own" means here: it is enforced in IAM, not
just in YAML.

### One-time GitHub setup

These are browser steps - they configure GitHub, not AWS, and the AWS side is already applied.

1. **Repository variable** - Settings → Secrets and variables → Actions → Variables:
   `AWS_ACCOUNT_ID` = the 12-digit account ID.
2. **Environments** - Settings → Environments, create `dev`, `test`, `prod`.
   Leave `dev` open; add yourself as a **required reviewer** on `test` and `prod`.
   The environment names must match exactly, or the OIDC subject claim will not match the
   IAM trust policy and the job will fail to assume its role.
3. **Branch protection** - Settings → Rules: require a pull request for `master`, and
   require the `fmt + validate` and `plan (dev|test|prod)` checks to pass.

## Tearing an environment down

Destroying `test` or `prod` leaves `dev` completely untouched, by design - but only because
of two deliberate choices, so do not undo them:

- `manage_lake_formation_account_settings = false` in those environments. That account-wide
  Lake Formation object is a singleton owned by `dev`; if `test` owned a copy, destroying
  `test` would delete it and re-enable the `IAMAllowedPrincipals` default grant account-wide,
  silently breaking `dev`'s column-level PII masking.
- The CI roles live in `terraform/github-oidc/`, not inside any environment. **Do not destroy
  that** - it is what GitHub Actions authenticates with for all three environments.

The data lake buckets are versioned and have no `force_destroy`, so `terraform destroy` fails
with `BucketNotEmpty` until they are emptied - versions and delete markers included, which
`aws s3 rm --recursive` does not remove:

```bash
ENV=test   # or prod

for layer in raw cleansed curated scripts logs; do
  B="meridian-${layer}-${ENV}-myk"
  echo "emptying $B"
  aws s3 rm "s3://$B" --recursive
  # Versioned buckets keep old versions and delete markers behind after the above.
  while true; do
    JSON=$(aws s3api list-object-versions --bucket "$B" --max-items 500       --query '{Objects: [].{Key:Key,VersionId:VersionId}}' --output json 2>/dev/null)
    COUNT=$(echo "$JSON" | python -c "import json,sys; d=json.load(sys.stdin); print(len(d.get('Objects') or []))")
    [ "$COUNT" = "0" ] && break
    aws s3api delete-objects --bucket "$B" --delete "$JSON" >/dev/null
  done
done

cd terraform/environments/${ENV}
terraform destroy
```

Two notes on what survives:

- The KMS key is scheduled for deletion with a 30-day window rather than deleted outright,
  so it lingers (and bills ~$1/month) until that window expires. That window is not
  shortenable below 7 days; cancel it with `aws kms cancel-key-deletion` if you want the
  environment back sooner.
- The state file itself remains in the state bucket. That is intentional - re-applying the
  environment later starts from a clean, empty state rather than a missing one.


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

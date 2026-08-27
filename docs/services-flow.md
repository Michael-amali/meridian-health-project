# Services Walkthrough — What Runs, When, and Why

This doc exists to answer "why does this service exist / why not something simpler?"
for every AWS service in the platform. Read it alongside `architecture.md` (which
shows the diagram) — this one narrates the flow in plain language and justifies each
design decision.

## Part 1 — Follow a batch record through the whole pipeline

Example: a synthetic "patient visit" record, from birth to dashboard.

1. **EventBridge Scheduler** fires on a cron-like schedule (e.g. daily at 2am) and
   invokes the **batch generator Lambda**. Nothing else is running in between — the
   Lambda doesn't need to be "always on", it just needs to wake up at the right time.
2. The **batch generator** (plain Python) fabricates realistic visit records and
   writes them as CSV/JSON to **S3 `raw/visits/`**, partitioned by date. This is the
   landing zone — nothing has touched or validated the data yet.
3. **Step Functions** (a state machine, triggered by its own EventBridge schedule
   once the batch window has passed) kicks off the actual pipeline:
   a. Runs a **Glue Crawler** over `raw/visits/` so the **Glue Data Catalog** knows
      the schema (columns, types) exists and is queryable.
   b. Runs a **Glue Job** (PySpark) that reads raw, deduplicates, standardizes types,
      tags PII columns (patient name, DOB), and writes Parquet to **S3 `cleansed/`**.
   c. Runs a **Glue Data Quality** check against the cleansed output — e.g. "no null
      patient_id", "visit_date is a valid date", "facility_id exists in dim_facility".
      If it fails, the state machine **stops and alerts** instead of pushing bad data
      forward.
   d. Runs another **Glue Job** that joins/aggregates cleansed data into the star
      schema (`fact_patient_visit`, joined against `dim_patient`, `dim_facility`, etc.)
      and writes to **S3 `curated/`**.
   e. Loads the curated Parquet into **Redshift Serverless** via `COPY`.
   f. Sends a success/failure notification via **SNS**.
4. **Lake Formation** sits on top of the Catalog the whole time, enforcing that only
   authorized roles can see unmasked PII columns — this doesn't move data anywhere,
   it's a permissions layer checked on every query.
5. **QuickSight** has a SPICE dataset that refreshes from Redshift on a schedule; the
   Executive and Operational dashboards read from SPICE (fast, cached), not live from
   Redshift on every click.
6. **CloudWatch** watched every step above for errors/duration the whole time; if
   anything breaks, an **alarm** fires into **SNS**.

## Part 2 — Follow a streaming event (a bedside vitals reading)

Streaming is architecturally different because the data needs to be actioned in
near-real-time (a dangerous heart rate can't wait for tomorrow's batch job) — that's
the whole reason this path exists separately from Part 1.

1. **EventBridge Scheduler** (a short interval, ~1/min) invokes the **streaming
   producer Lambda** — again, nothing is "always on"; this Lambda just wakes up,
   emits one batch of synthetic vitals/prescription events, and exits.
2. The producer pushes JSON events onto **Kinesis Data Streams** (on-demand mode).
   Kinesis is a durable, ordered buffer — it decouples "something produced an event"
   from "something consumed it," so producers and consumers scale independently and
   a slow consumer doesn't lose data.
3. Two independent consumers read the same stream:
   - **Kinesis Firehose** batches records over a short buffer window and writes them
     to **S3 `raw/vitals/`** as Parquet — this is the durable copy that eventually
     joins the batch pipeline (crawled, cleansed, curated, loaded into Redshift) so
     historical trends are queryable later.
   - The **`stream_alerting` Lambda** reads the stream directly (lower latency than
     waiting for Firehose's buffer) and checks each event against simple thresholds
     (e.g. heart rate > 150). Anything critical gets written to a **DynamoDB
     `active_alerts`** table.
4. The **Operational/Clinical QuickSight dashboard** reads `active_alerts` from
   DynamoDB for its near-real-time "current critical alerts" panel — this is the one
   piece of the whole platform that deliberately bypasses Redshift/SPICE, because
   SPICE's refresh cadence is too slow for "alert a nurse right now."

## Part 3 — Why these specific services (the decisions you asked about)

**Why EventBridge Scheduler at all — why not just run the Lambda on a loop, or use
cron on a server?**
There's no server to put cron on (serverless-first goal) and Lambda has no built-in
"run me every day at 2am" — something external has to invoke it. EventBridge
Scheduler is that trigger: it's free at this scale, requires no infrastructure to
maintain, and is the standard AWS-native way to invoke a Lambda/state machine on a
schedule. The alternative (a long-running EC2 box with a cron job) would cost money
24/7 to do something that only needs to happen once a day or once a minute.

**Why two separate EventBridge schedules (batch generator vs. streaming producer)
instead of one?**
They run at completely different cadences (daily/weekly vs. ~1/min) and trigger
different Lambdas for unrelated reasons. Combining them would mean one schedule
doing two jobs, which is harder to reason about and to change independently later
(e.g. changing the streaming interval shouldn't risk touching the batch schedule).

**Why Kinesis Data Streams *and* Firehose — why not just write straight to S3?**
Kinesis Data Streams exists because two different consumers need the *same* events
for two different purposes at two different speeds (the alerting Lambda needs it
immediately; the historical record can tolerate a short delay). A stream is what
lets multiple independent consumers read the same data without one blocking the
other. Firehose then exists purely to solve "batch these into reasonably-sized
Parquet files in S3" — writing every single event as its own tiny S3 object would be
slow to query and expensive at scale.

**Why Step Functions instead of just chaining Lambda calls or Glue job triggers
manually?**
The pipeline has a strict order (crawl → cleanse → DQ-gate → curate → load) where a
failure at any step should stop the rest and notify someone, and a transient failure
(e.g. Glue job hiccup) should retry automatically without a human re-running
anything. Step Functions gives you that retry/catch/branching logic as configuration
instead of as code you'd have to write and maintain yourself, and it gives you a
visual execution history when something does go wrong — important for the RFP's
"recovers without manual data-fixing" requirement.

**Why does Glue Data Quality gate the pipeline instead of just checking data quality
in a dashboard after the fact?**
Gating means bad data (e.g. a visit record with no patient_id) never reaches the
curated layer or the warehouse in the first place — it fails loudly and stops there.
Checking quality only after loading it into Redshift means executives could already
be looking at wrong numbers before anyone notices.

**Why Lake Formation instead of just IAM policies on the S3 buckets?**
IAM on S3 buckets can only say "this role can/can't read this bucket/prefix" — it
has no concept of "this role can see the diagnosis column but not the patient name
column in the same table." Lake Formation adds column- and row-level permissions on
top of the Glue Catalog, which is what's needed to give an operational analyst
de-identified data while an authorized role sees the real thing, all from the same
underlying table.

**Why Redshift Serverless instead of a normal provisioned Redshift cluster?**
A provisioned cluster costs money whether or not anyone is querying it. This
capstone's query pattern is bursty (dashboard refreshes, ad-hoc analysis) with long
idle stretches, so Serverless — which auto-scales and can pause — matches actual
usage instead of paying for constant capacity.

**Why QuickSight SPICE instead of dashboards querying Redshift directly?**
SPICE is QuickSight's in-memory cache — dashboards load fast for viewers and don't
hammer Redshift with a fresh query every time someone opens a chart. The tradeoff
(data is only as fresh as the last SPICE refresh) is fine for exec/operational
trend dashboards, which is why the one truly real-time need (active critical alerts)
was deliberately routed around SPICE straight to DynamoDB instead (see Part 2).

**Why Terraform modules + separate dev/test/prod environments instead of one set of
resources?**
The RFP explicitly requires demonstrating a promotion path (a change is tested in
dev/test before it ever touches prod). Modules mean the same infrastructure
definition is reused across all three environments (via per-env tfvars) instead of
copy-pasted three times, so a fix only needs to be made once.

## Quick-reference table

| Service | Role in the flow | Why chosen over the obvious alternative |
|---|---|---|
| EventBridge Scheduler | Wakes up Lambdas/Step Functions on a schedule | No server needed to run cron on |
| Lambda (generators) | Produces synthetic data | Pay-per-invocation, no idle cost |
| Kinesis Data Streams | Durable buffer, multiple independent consumers | Decouples producer speed from consumer speed |
| Kinesis Firehose | Batches stream into Parquet in S3 | Avoids one-tiny-file-per-event in S3 |
| Lambda (stream_alerting) | Low-latency read of the stream for critical events | Firehose's buffer window is too slow for alerting |
| DynamoDB (active_alerts) | Near-real-time alert store for the ops dashboard | Sub-second reads/writes, no batch/refresh delay |
| S3 (raw/cleansed/curated) | Data lake, one prefix per quality tier | Cheap, durable, natural fit for Parquet + partitioning |
| Glue Crawler | Registers schemas into the Catalog | Avoids hand-maintaining table DDL |
| Glue Jobs (PySpark) | Cleansing and dimensional-modeling transforms | Serverless Spark, no cluster to manage |
| Glue Data Quality | Gates promotion on data correctness | Stops bad data before it reaches the warehouse |
| Glue Data Catalog | Central schema registry, used by Glue/Athena/Redshift Spectrum/Lake Formation | One source of truth for table definitions |
| Lake Formation | Column/row-level access control | IAM alone can't do column-level masking |
| Step Functions | Orchestrates the multi-step pipeline with retry/catch | Declarative retries instead of custom glue code |
| Redshift Serverless | Warehouse for BI queries | Auto-pause/scale matches bursty query pattern |
| QuickSight (SPICE) | Executive + Operational dashboards | Fast, cached reads; isolates dashboards from Redshift load |
| CloudWatch + SNS | Monitoring and failure alerting | Native, no extra monitoring stack to run |
| Terraform (modules + envs) | Infrastructure as code across dev/test/prod | Reusable definition, required promotion path |
| GitHub Actions | CI/CD: plan on PR, apply on merge | Automates the promotion path instead of manual applies |

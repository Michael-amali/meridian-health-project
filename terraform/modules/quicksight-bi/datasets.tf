# Phase 7: the six datasets both dashboards are built from.
#
# Each one is a SQL query against the Phase 6 star schema rather than a raw
# table import, for three reasons worth stating once here:
#   1. Every timestamp-shaped column in the warehouse is a VARCHAR (see
#      modules/redshift-warehouse/schema.tf for why). Casting here is what
#      lets QuickSight treat them as real dates and offer day/month rollups.
#   2. Facility names live in dim_facility, and a dashboard that says FAC02
#      instead of "Meridian North - Rivertown" is not a dashboard an
#      executive will use. The join happens once, here, not in every visual.
#   3. Anything a visual needs to count is turned into a 0/1 integer column
#      in SQL (denied_flag, at_capacity_risk, stockout_flag, ...). Summing an
#      integer is obvious to anyone reading the visual later; the equivalent
#      QuickSight expression over a boolean is not.
#
# The structure of all six resources is genuinely identical - only the name,
# the query and its column list differ - so they are one for_each over the
# map below rather than six near-copies. All the actual decision-making is in
# the SQL, which is right here in the map.

locals {
  # QuickSight needs the column list up front, in the same order as the
  # SELECT, using its own type names: STRING, INTEGER, DECIMAL or DATETIME.
  dashboard_datasets = {
    visits = {
      name = "Meridian visits"
      sql  = <<-SQL
        WITH visits AS (
          SELECT
            visit_id,
            patient_id,
            facility_id,
            department,
            visit_type,
            attending_staff_id,
            CAST(admission_ts AS TIMESTAMP) AS admission_time,
            CAST(discharge_ts AS TIMESTAMP) AS discharge_time,
            still_admitted,
            length_of_stay_hours
          FROM fact_patient_visit
        ),
        with_prior_visit AS (
          SELECT
            visits.*,
            LAG(discharge_time) OVER (PARTITION BY patient_id ORDER BY admission_time) AS prior_discharge_time
          FROM visits
        )
        SELECT
          v.visit_id,
          v.patient_id,
          v.facility_id,
          f.facility_name,
          v.department,
          v.visit_type,
          v.attending_staff_id,
          v.admission_time,
          CAST(v.admission_time AS DATE) AS admission_date,
          v.length_of_stay_hours,
          CASE WHEN v.still_admitted THEN 1 ELSE 0 END AS still_admitted_flag,
          CASE
            WHEN v.prior_discharge_time IS NOT NULL
             AND v.admission_time <= DATEADD(day, 30, v.prior_discharge_time)
            THEN 1 ELSE 0
          END AS readmission_flag
        FROM with_prior_visit v
        JOIN dim_facility f ON f.facility_id = v.facility_id
      SQL
      # readmission_flag above is the RFP's readmission metric: this patient
      # arriving again within 30 days of their own previous discharge. The
      # LAG window function supplies that previous discharge, so no self-join
      # is needed.
      columns = [
        { name = "visit_id", type = "STRING" },
        { name = "patient_id", type = "STRING" },
        { name = "facility_id", type = "STRING" },
        { name = "facility_name", type = "STRING" },
        { name = "department", type = "STRING" },
        { name = "visit_type", type = "STRING" },
        { name = "attending_staff_id", type = "STRING" },
        { name = "admission_time", type = "DATETIME" },
        { name = "admission_date", type = "DATETIME" },
        { name = "length_of_stay_hours", type = "DECIMAL" },
        { name = "still_admitted_flag", type = "INTEGER" },
        { name = "readmission_flag", type = "INTEGER" },
      ]
    }

    bed_occupancy = {
      name = "Meridian bed occupancy"
      sql  = <<-SQL
        SELECT
          b.facility_id,
          f.facility_name,
          b.department,
          CAST(b.snapshot_date AS DATE) AS snapshot_date,
          b.total_beds,
          b.occupied_beds,
          b.occupancy_rate,
          CASE WHEN b.occupancy_rate >= 0.90 THEN 1 ELSE 0 END AS at_capacity_risk
        FROM fact_bed_occupancy b
        JOIN dim_facility f ON f.facility_id = b.facility_id
      SQL
      # occupancy_rate is a fraction between 0 and 1. 90% is the point at
      # which a department has effectively no surge capacity left, which is
      # what the operational dashboard's capacity-risk count means by "risk".
      columns = [
        { name = "facility_id", type = "STRING" },
        { name = "facility_name", type = "STRING" },
        { name = "department", type = "STRING" },
        { name = "snapshot_date", type = "DATETIME" },
        { name = "total_beds", type = "INTEGER" },
        { name = "occupied_beds", type = "INTEGER" },
        { name = "occupancy_rate", type = "DECIMAL" },
        { name = "at_capacity_risk", type = "INTEGER" },
      ]
    }

    claims = {
      name = "Meridian claims"
      sql  = <<-SQL
        SELECT
          c.claim_id,
          c.patient_id,
          c.facility_id,
          f.facility_name,
          c.payer,
          c.status,
          c.claim_amount,
          CAST(c.service_date AS DATE) AS service_date,
          CASE WHEN c.status = 'Denied' THEN 1 ELSE 0 END AS denied_flag,
          CASE WHEN c.status = 'Paid' THEN c.claim_amount ELSE 0 END AS paid_amount
        FROM fact_claim c
        JOIN dim_facility f ON f.facility_id = c.facility_id
      SQL
      columns = [
        { name = "claim_id", type = "STRING" },
        { name = "patient_id", type = "STRING" },
        { name = "facility_id", type = "STRING" },
        { name = "facility_name", type = "STRING" },
        { name = "payer", type = "STRING" },
        { name = "status", type = "STRING" },
        { name = "claim_amount", type = "DECIMAL" },
        { name = "service_date", type = "DATETIME" },
        { name = "denied_flag", type = "INTEGER" },
        { name = "paid_amount", type = "DECIMAL" },
      ]
    }

    staffing = {
      name = "Meridian staffing"
      sql  = <<-SQL
        WITH shift_totals AS (
          SELECT
            facility_id,
            department,
            CAST(shift_date AS DATE) AS shift_date,
            shift_name,
            COUNT(*) AS staff_count,
            SUM(CASE WHEN role = 'Nurse' THEN 1 ELSE 0 END) AS nurse_count,
            SUM(CASE WHEN role = 'Physician' THEN 1 ELSE 0 END) AS physician_count
          FROM fact_staffing
          GROUP BY 1, 2, 3, 4
        ),
        bed_totals AS (
          SELECT
            facility_id,
            department,
            CAST(snapshot_date AS DATE) AS snapshot_date,
            SUM(occupied_beds) AS occupied_beds
          FROM fact_bed_occupancy
          GROUP BY 1, 2, 3
        )
        SELECT
          s.facility_id,
          f.facility_name,
          s.department,
          s.shift_date,
          s.shift_name,
          s.staff_count,
          s.nurse_count,
          s.physician_count,
          b.occupied_beds,
          CASE
            WHEN s.staff_count > 0 AND b.occupied_beds IS NOT NULL
            THEN ROUND(CAST(b.occupied_beds AS DECIMAL(10, 2)) / s.staff_count, 2)
          END AS beds_per_staff
        FROM shift_totals s
        JOIN dim_facility f ON f.facility_id = s.facility_id
        LEFT JOIN bed_totals b
          ON  b.facility_id   = s.facility_id
          AND b.department    = s.department
          AND b.snapshot_date = s.shift_date
      SQL
      # beds_per_staff is the RFP's staffing ratio: how many occupied beds
      # each rostered staff member is covering on that shift, so higher is
      # worse. The LEFT JOIN means a shift with no bed snapshot yet leaves it
      # null rather than reading as a perfectly staffed zero.
      columns = [
        { name = "facility_id", type = "STRING" },
        { name = "facility_name", type = "STRING" },
        { name = "department", type = "STRING" },
        { name = "shift_date", type = "DATETIME" },
        { name = "shift_name", type = "STRING" },
        { name = "staff_count", type = "INTEGER" },
        { name = "nurse_count", type = "INTEGER" },
        { name = "physician_count", type = "INTEGER" },
        { name = "occupied_beds", type = "INTEGER" },
        { name = "beds_per_staff", type = "DECIMAL" },
      ]
    }

    pharmacy_stock = {
      name = "Meridian pharmacy stock"
      sql  = <<-SQL
        SELECT
          p.facility_id,
          f.facility_name,
          p.drug_name,
          CAST(p.snapshot_date AS DATE) AS snapshot_date,
          p.current_stock,
          p.reorder_threshold,
          p.unit_cost,
          p.current_stock * p.unit_cost AS stock_value,
          CASE WHEN p.stockout_risk THEN 1 ELSE 0 END AS stockout_flag
        FROM fact_pharmacy_inventory p
        JOIN dim_facility f ON f.facility_id = p.facility_id
      SQL
      columns = [
        { name = "facility_id", type = "STRING" },
        { name = "facility_name", type = "STRING" },
        { name = "drug_name", type = "STRING" },
        { name = "snapshot_date", type = "DATETIME" },
        { name = "current_stock", type = "INTEGER" },
        { name = "reorder_threshold", type = "INTEGER" },
        { name = "unit_cost", type = "DECIMAL" },
        { name = "stock_value", type = "DECIMAL" },
        { name = "stockout_flag", type = "INTEGER" },
      ]
    }

    vitals_alerts = {
      name = "Meridian critical vitals alerts"
      sql  = <<-SQL
        SELECT
          a.event_id,
          a.patient_id,
          a.facility_id,
          f.facility_name,
          CAST(a.event_ts AS TIMESTAMP) AS event_time,
          a.heart_rate,
          a.spo2,
          a.systolic_bp,
          a.diastolic_bp,
          a.temperature_c,
          CASE WHEN a.heart_rate_breach THEN 1 ELSE 0 END AS heart_rate_breach,
          CASE WHEN a.spo2_breach THEN 1 ELSE 0 END AS spo2_breach,
          CASE WHEN a.systolic_bp_breach THEN 1 ELSE 0 END AS systolic_bp_breach,
          CASE WHEN a.temperature_breach THEN 1 ELSE 0 END AS temperature_breach
        FROM fact_vitals_alert a
        JOIN dim_facility f ON f.facility_id = a.facility_id
      SQL
      # fact_vitals_alert already holds only the readings that breached a
      # clinical threshold (see src/glue_jobs/silver_to_gold/
      # fact_vitals_alert.py), so every row here is an alert - no further
      # filtering needed, and a plain row count is the alert count.
      columns = [
        { name = "event_id", type = "STRING" },
        { name = "patient_id", type = "STRING" },
        { name = "facility_id", type = "STRING" },
        { name = "facility_name", type = "STRING" },
        { name = "event_time", type = "DATETIME" },
        { name = "heart_rate", type = "DECIMAL" },
        { name = "spo2", type = "DECIMAL" },
        { name = "systolic_bp", type = "DECIMAL" },
        { name = "diastolic_bp", type = "DECIMAL" },
        { name = "temperature_c", type = "DECIMAL" },
        { name = "heart_rate_breach", type = "INTEGER" },
        { name = "spo2_breach", type = "INTEGER" },
        { name = "systolic_bp_breach", type = "INTEGER" },
        { name = "temperature_breach", type = "INTEGER" },
      ]
    }
  }
}

resource "aws_quicksight_data_set" "dashboard" {
  for_each = local.dashboard_datasets

  data_set_id = "meridian-${replace(each.key, "_", "-")}-${var.env}"
  name        = "${each.value.name} (${var.env})"

  # SPICE, not direct query: the dashboards then read from QuickSight's own
  # cache, and the Redshift workgroup only has to wake up on the refresh
  # schedule (refresh.tf) rather than every time somebody opens a dashboard.
  import_mode = "SPICE"

  physical_table_map {
    # Hyphens, not underscores: QuickSight validates this key against
    # [0-9a-zA-Z-]* and rejects the map outright otherwise. The custom_sql
    # name below is just a label and has no such restriction.
    physical_table_map_id = replace(each.key, "_", "-")

    custom_sql {
      data_source_arn = aws_quicksight_data_source.redshift.arn
      name            = each.key
      sql_query       = each.value.sql

      dynamic "columns" {
        for_each = each.value.columns
        content {
          name = columns.value.name
          type = columns.value.type
        }
      }
    }
  }

  # Every dashboard dataset carries facility_id, so all six can be scoped by
  # the same rules dataset. That is why the executive and operational
  # dashboards share datasets instead of needing two parallel sets that
  # differ only in whether row-level security is switched on.
  row_level_permission_data_set {
    arn               = aws_quicksight_data_set.facility_access.arn
    permission_policy = "GRANT_ACCESS"
    format_version    = "VERSION_1"
    status            = "ENABLED"
  }

  permissions {
    principal = local.admin_user_arn
    actions   = local.data_set_owner_actions
  }

  tags = var.tags
}

# prod - structurally identical to dev, and idle for the same reasons as test.
#
# In a real deployment this is the environment with the schedules ON and real
# source systems feeding it. Here the "sources" are synthetic generators we
# wrote ourselves, so leaving them running would spend money producing fake data
# nobody looks at. The switches below are the ONLY difference from dev; flip
# them to true and prod behaves exactly like dev, because the code is byte-for-
# byte the code dev runs.

env = "prod"

alert_email                = "michaelacheampongy@gmail.com"
quicksight_admin_user_name = "Michael-Ach"

quicksight_facility_access = {
  "Michael-Ach"   = null
  "fac01-manager" = "FAC01"
  "fac02-manager" = "FAC02"
  "fac03-manager" = "FAC03"
}

# Both sides idle. Nothing here runs unattended.
batch_schedules_enabled = false

streaming_enabled = false

quicksight_refresh_schedules_enabled = false

redshift_base_capacity = 8

# dev owns this. Leave it false. See variables.tf.
manage_lake_formation_account_settings = false

# One-time warehouse bootstrap SQL. See the variable description before
# changing this - true only for the apply that creates a NEW environment.
run_warehouse_bootstrap = false

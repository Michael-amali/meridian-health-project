# dev - the working environment, and the only one where anything runs on a
# timer. Values here describe what dev is actually doing today, so `terraform
# apply` against dev is a no-op rather than a surprise.

env = "dev"

alert_email                = "michaelacheampongy@gmail.com"
quicksight_admin_user_name = "Michael-Ach"

quicksight_facility_access = {
  "Michael-Ach"   = null
  "fac01-manager" = "FAC01"
  "fac02-manager" = "FAC02"
  "fac03-manager" = "FAC03"
}

# The batch side carries the daily story - generators at 06:00-06:20 UTC, the
# batch-daily pipeline at 08:00 UTC - so it stays on.
batch_schedules_enabled = true

# The streaming side is off, deliberately: the producer and the every-30-minutes
# curation pipeline are the expensive half, and there is no value in them
# running unattended between demos. Everything still exists and can be started
# by hand. Flip to true when you want live vitals flowing again.
streaming_enabled = false

quicksight_refresh_schedules_enabled = true

redshift_base_capacity = 8

# dev owns the account-wide Lake Formation settings. test and prod must leave
# this false - see the variable's description in variables.tf.
manage_lake_formation_account_settings = true

# One-time warehouse bootstrap SQL. See the variable description before
# changing this - true only for the apply that creates a NEW environment.
run_warehouse_bootstrap = false

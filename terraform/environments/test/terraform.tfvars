# test - structurally identical to dev, but idle.
#
# Every resource dev has exists here too, which is the point: a change that
# applies cleanly to test is a change that will apply cleanly to prod. What test
# does NOT do is generate synthetic data or run pipelines on a timer, because
# nothing would be reading the results. Run them by hand when you want to
# verify something:
#
#   aws lambda invoke --function-name meridian-gen-visits-test /dev/null
#   aws stepfunctions start-execution --state-machine-arn <batch_daily_state_machine_arn>

env = "test"

# No email subscription here - pipeline alerts from a test environment would
# just be noise in the inbox that already gets the dev ones.
alert_email                = null
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

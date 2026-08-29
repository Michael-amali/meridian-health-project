# Phase 7: when each SPICE dataset reloads from Redshift.
#
# The two cadences are deliberate, not a default. Phase 5's batch pipeline
# runs at 08:00 UTC and takes well under two hours end to end, so 10:00 UTC
# is the first moment a daily refresh is guaranteed to pick up a complete
# day. The critical-vitals dataset is the one thing on these dashboards that
# is meant to be near-real-time - Phase 5's streaming pipeline recurates it
# every 30 minutes - so it refreshes hourly instead.
#
# Every refresh wakes the Redshift Serverless workgroup and bills RPU
# seconds, which is the whole reason this is 5 daily refreshes plus 24 hourly
# ones rather than everything on the fast cadence.

locals {
  hourly_refresh_dataset = "vitals_alerts"
}

resource "aws_quicksight_refresh_schedule" "daily" {
  for_each = {
    for key, config in local.dashboard_datasets : key => config
    if key != local.hourly_refresh_dataset
  }

  data_set_id = aws_quicksight_data_set.dashboard[each.key].data_set_id
  schedule_id = "daily-after-batch-pipeline"

  schedule {
    refresh_type = "FULL_REFRESH"

    schedule_frequency {
      interval        = "DAILY"
      time_of_the_day = "10:00"
      timezone        = "UTC"
    }
  }
}

resource "aws_quicksight_refresh_schedule" "hourly" {
  data_set_id = aws_quicksight_data_set.dashboard[local.hourly_refresh_dataset].data_set_id
  schedule_id = "hourly-streaming-alerts"

  schedule {
    refresh_type = "FULL_REFRESH"

    schedule_frequency {
      interval = "HOURLY"
      timezone = "UTC"
    }
  }
}

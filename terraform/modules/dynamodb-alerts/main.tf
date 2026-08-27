# "Active alerts" table for the stream_alerting Lambda: one item per
# dangerous vitals reading, used by the operational dashboard's
# near-real-time alert view (Phase 7). PAY_PER_REQUEST because alert volume
# is small and bursty - provisioned capacity would just be paying for idle.
#
# TTL auto-expires alerts ~24h after they're written (see expires_at in
# src/lambdas/stream_alerting/handler.py) so this table never grows
# unbounded - it's meant to reflect *active* alerts, not a permanent log.

resource "aws_dynamodb_table" "active_alerts" {
  name         = "meridian-active-alerts-${var.env}"
  billing_mode = "PAY_PER_REQUEST"

  hash_key  = "patient_id"
  range_key = "alert_id"

  attribute {
    name = "patient_id"
    type = "S"
  }

  attribute {
    name = "alert_id"
    type = "S"
  }

  ttl {
    attribute_name = "expires_at"
    enabled        = true
  }

  tags = merge(var.tags, { Name = "meridian-active-alerts-${var.env}" })
}

# Phase 7: the Executive dashboard - the network-wide view the RFP asks
# leadership to run the hospital network from.
#
# Read this file top to bottom as: which datasets the sheet may use, then one
# block per visual in the order they appear on screen, then the grid that
# places them. Every visual names its dataset through the short identifiers
# declared at the top rather than an ARN, which is what makes the visual
# blocks readable at all.
#
# Only a dashboard is created, not a QuickSight analysis. A dashboard is the
# published, read-only artifact; an analysis is the editable draft behind it.
# Defining both in Terraform would mean maintaining the same 300 lines of
# visual definitions twice, and anyone who wants to edit these visually can
# use "Save as analysis" from the dashboard itself.

locals {
  dashboard_owner_actions = [
    "quicksight:DescribeDashboard",
    "quicksight:ListDashboardVersions",
    "quicksight:QueryDashboard",
    "quicksight:UpdateDashboard",
    "quicksight:DeleteDashboard",
    "quicksight:DescribeDashboardPermissions",
    "quicksight:UpdateDashboardPermissions",
    "quicksight:UpdateDashboardPublishedVersion",
  ]
}

resource "aws_quicksight_dashboard" "executive" {
  dashboard_id        = "meridian-executive-${var.env}"
  name                = "Meridian Executive Overview (${var.env})"
  version_description = "Phase 7 - network-wide and per-facility performance"

  definition {
    data_set_identifiers_declarations {
      identifier   = "claims"
      data_set_arn = aws_quicksight_data_set.dashboard["claims"].arn
    }

    data_set_identifiers_declarations {
      identifier   = "visits"
      data_set_arn = aws_quicksight_data_set.dashboard["visits"].arn
    }

    data_set_identifiers_declarations {
      identifier   = "bed_occupancy"
      data_set_arn = aws_quicksight_data_set.dashboard["bed_occupancy"].arn
    }

    data_set_identifiers_declarations {
      identifier   = "staffing"
      data_set_arn = aws_quicksight_data_set.dashboard["staffing"].arn
    }

    # Two ratios that only make sense as a division of two aggregates, so
    # they cannot be precomputed as columns in datasets.tf the way the 0/1
    # flags are - a row-level readmission rate would be meaningless.
    calculated_fields {
      data_set_identifier = "visits"
      name                = "readmission_rate"
      expression          = "sum({readmission_flag}) / count({visit_id})"
    }

    calculated_fields {
      data_set_identifier = "claims"
      name                = "denial_rate"
      expression          = "sum({denied_flag}) / count({claim_id})"
    }

    sheets {
      sheet_id = "executive-overview"
      name     = "Executive overview"
      title    = "Meridian Health Network - executive overview"

      # --- Top row: the four numbers leadership asked to see first ---

      visuals {
        kpi_visual {
          visual_id = "kpi-total-visits"

          title {
            format_text {
              plain_text = "Total patient visits"
            }
          }

          chart_configuration {
            field_wells {
              values {
                categorical_measure_field {
                  field_id             = "kpi-total-visits.visit_id"
                  aggregation_function = "COUNT"

                  column {
                    column_name         = "visit_id"
                    data_set_identifier = "visits"
                  }
                }
              }
            }
          }
        }
      }

      visuals {
        kpi_visual {
          visual_id = "kpi-avg-length-of-stay"

          # The RFP asks about patient wait times. The synthetic sources
          # carry admission and discharge timestamps but no separate
          # triage/wait clock, so average length of stay is the closest
          # honest throughput measure available - see docs for the gap.
          title {
            format_text {
              plain_text = "Avg length of stay (hours)"
            }
          }

          chart_configuration {
            field_wells {
              values {
                numerical_measure_field {
                  field_id = "kpi-avg-length-of-stay.length_of_stay_hours"

                  column {
                    column_name         = "length_of_stay_hours"
                    data_set_identifier = "visits"
                  }

                  aggregation_function {
                    simple_numerical_aggregation = "AVERAGE"
                  }
                }
              }
            }
          }
        }
      }

      visuals {
        kpi_visual {
          visual_id = "kpi-readmission-rate"

          title {
            format_text {
              plain_text = "30-day readmission rate"
            }
          }

          chart_configuration {
            field_wells {
              values {
                numerical_measure_field {
                  # No aggregation_function: readmission_rate is already an
                  # aggregate expression (see calculated_fields above).
                  field_id = "kpi-readmission-rate.readmission_rate"

                  column {
                    column_name         = "readmission_rate"
                    data_set_identifier = "visits"
                  }
                }
              }
            }
          }
        }
      }

      visuals {
        kpi_visual {
          visual_id = "kpi-claim-revenue"

          title {
            format_text {
              plain_text = "Total claim value"
            }
          }

          chart_configuration {
            field_wells {
              values {
                numerical_measure_field {
                  field_id = "kpi-claim-revenue.claim_amount"

                  column {
                    column_name         = "claim_amount"
                    data_set_identifier = "claims"
                  }

                  aggregation_function {
                    simple_numerical_aggregation = "SUM"
                  }
                }
              }
            }
          }
        }
      }

      # --- Capacity and demand ---

      visuals {
        line_chart_visual {
          visual_id = "line-occupancy-trend"

          title {
            format_text {
              plain_text = "Bed occupancy rate by facility"
            }
          }

          chart_configuration {
            type = "LINE"

            field_wells {
              line_chart_aggregated_field_wells {
                category {
                  date_dimension_field {
                    field_id         = "line-occupancy-trend.snapshot_date"
                    hierarchy_id     = "line-occupancy-trend.snapshot_date"
                    date_granularity = "DAY"

                    column {
                      column_name         = "snapshot_date"
                      data_set_identifier = "bed_occupancy"
                    }
                  }
                }

                colors {
                  categorical_dimension_field {
                    field_id = "line-occupancy-trend.facility_name"

                    column {
                      column_name         = "facility_name"
                      data_set_identifier = "bed_occupancy"
                    }
                  }
                }

                values {
                  numerical_measure_field {
                    field_id = "line-occupancy-trend.occupancy_rate"

                    column {
                      column_name         = "occupancy_rate"
                      data_set_identifier = "bed_occupancy"
                    }

                    aggregation_function {
                      simple_numerical_aggregation = "AVERAGE"
                    }
                  }
                }
              }
            }
          }

          # QuickSight creates a date-time drill-down hierarchy of its own for
          # any date field on a line chart and echoes it back on read.
          # Declaring it here, with the id QuickSight itself generates, is what
          # keeps `terraform plan` clean instead of showing the same phantom
          # change forever.
          column_hierarchies {
            date_time_hierarchy {
              hierarchy_id = "line-occupancy-trend.snapshot_date"
            }
          }
        }
      }

      visuals {
        bar_chart_visual {
          visual_id = "bar-visits-by-facility"

          title {
            format_text {
              plain_text = "Visits by facility and visit type"
            }
          }

          chart_configuration {
            bars_arrangement = "STACKED"
            orientation      = "VERTICAL"

            field_wells {
              bar_chart_aggregated_field_wells {
                category {
                  categorical_dimension_field {
                    field_id = "bar-visits-by-facility.facility_name"

                    column {
                      column_name         = "facility_name"
                      data_set_identifier = "visits"
                    }
                  }
                }

                colors {
                  categorical_dimension_field {
                    field_id = "bar-visits-by-facility.visit_type"

                    column {
                      column_name         = "visit_type"
                      data_set_identifier = "visits"
                    }
                  }
                }

                values {
                  categorical_measure_field {
                    field_id             = "bar-visits-by-facility.visit_id"
                    aggregation_function = "COUNT"

                    column {
                      column_name         = "visit_id"
                      data_set_identifier = "visits"
                    }
                  }
                }
              }
            }
          }
        }
      }

      # --- Financial performance ---

      visuals {
        line_chart_visual {
          visual_id = "line-claim-value-trend"

          title {
            format_text {
              plain_text = "Claim value over time by status"
            }
          }

          chart_configuration {
            type = "LINE"

            field_wells {
              line_chart_aggregated_field_wells {
                category {
                  date_dimension_field {
                    field_id         = "line-claim-value-trend.service_date"
                    hierarchy_id     = "line-claim-value-trend.service_date"
                    date_granularity = "DAY"

                    column {
                      column_name         = "service_date"
                      data_set_identifier = "claims"
                    }
                  }
                }

                colors {
                  categorical_dimension_field {
                    field_id = "line-claim-value-trend.status"

                    column {
                      column_name         = "status"
                      data_set_identifier = "claims"
                    }
                  }
                }

                values {
                  numerical_measure_field {
                    field_id = "line-claim-value-trend.claim_amount"

                    column {
                      column_name         = "claim_amount"
                      data_set_identifier = "claims"
                    }

                    aggregation_function {
                      simple_numerical_aggregation = "SUM"
                    }
                  }
                }
              }
            }
          }

          # QuickSight creates a date-time drill-down hierarchy of its own for
          # any date field on a line chart and echoes it back on read.
          # Declaring it here, with the id QuickSight itself generates, is what
          # keeps `terraform plan` clean instead of showing the same phantom
          # change forever.
          column_hierarchies {
            date_time_hierarchy {
              hierarchy_id = "line-claim-value-trend.service_date"
            }
          }
        }
      }

      visuals {
        bar_chart_visual {
          visual_id = "bar-denial-rate-by-payer"

          title {
            format_text {
              plain_text = "Claim denial rate by payer"
            }
          }

          chart_configuration {
            bars_arrangement = "CLUSTERED"
            orientation      = "HORIZONTAL"

            field_wells {
              bar_chart_aggregated_field_wells {
                category {
                  categorical_dimension_field {
                    field_id = "bar-denial-rate-by-payer.payer"

                    column {
                      column_name         = "payer"
                      data_set_identifier = "claims"
                    }
                  }
                }

                values {
                  numerical_measure_field {
                    field_id = "bar-denial-rate-by-payer.denial_rate"

                    column {
                      column_name         = "denial_rate"
                      data_set_identifier = "claims"
                    }
                  }
                }
              }
            }
          }
        }
      }

      # --- Staffing ---

      visuals {
        bar_chart_visual {
          visual_id = "bar-staffing-ratio"

          title {
            format_text {
              plain_text = "Staffing ratio - occupied beds per staff member (higher is worse)"
            }
          }

          chart_configuration {
            bars_arrangement = "CLUSTERED"
            orientation      = "VERTICAL"

            field_wells {
              bar_chart_aggregated_field_wells {
                category {
                  categorical_dimension_field {
                    field_id = "bar-staffing-ratio.facility_name"

                    column {
                      column_name         = "facility_name"
                      data_set_identifier = "staffing"
                    }
                  }
                }

                colors {
                  categorical_dimension_field {
                    field_id = "bar-staffing-ratio.department"

                    column {
                      column_name         = "department"
                      data_set_identifier = "staffing"
                    }
                  }
                }

                values {
                  numerical_measure_field {
                    field_id = "bar-staffing-ratio.beds_per_staff"

                    column {
                      column_name         = "beds_per_staff"
                      data_set_identifier = "staffing"
                    }

                    aggregation_function {
                      simple_numerical_aggregation = "AVERAGE"
                    }
                  }
                }
              }
            }
          }
        }
      }

      # --- Placement. The grid is 36 columns wide; row heights are in grid
      # rows, so the four KPIs across the top are 9 columns each. ---

      layouts {
        configuration {
          grid_layout {
            canvas_size_options {
              screen_canvas_size_options {
                resize_option = "RESPONSIVE"
              }
            }

            elements {
              element_id   = "kpi-total-visits"
              element_type = "VISUAL"
              column_index = 0
              column_span  = 9
              row_index    = 0
              row_span     = 4
            }

            elements {
              element_id   = "kpi-avg-length-of-stay"
              element_type = "VISUAL"
              column_index = 9
              column_span  = 9
              row_index    = 0
              row_span     = 4
            }

            elements {
              element_id   = "kpi-readmission-rate"
              element_type = "VISUAL"
              column_index = 18
              column_span  = 9
              row_index    = 0
              row_span     = 4
            }

            elements {
              element_id   = "kpi-claim-revenue"
              element_type = "VISUAL"
              column_index = 27
              column_span  = 9
              row_index    = 0
              row_span     = 4
            }

            elements {
              element_id   = "line-occupancy-trend"
              element_type = "VISUAL"
              column_index = 0
              column_span  = 18
              row_index    = 4
              row_span     = 9
            }

            elements {
              element_id   = "bar-visits-by-facility"
              element_type = "VISUAL"
              column_index = 18
              column_span  = 18
              row_index    = 4
              row_span     = 9
            }

            elements {
              element_id   = "line-claim-value-trend"
              element_type = "VISUAL"
              column_index = 0
              column_span  = 18
              row_index    = 13
              row_span     = 9
            }

            elements {
              element_id   = "bar-denial-rate-by-payer"
              element_type = "VISUAL"
              column_index = 18
              column_span  = 18
              row_index    = 13
              row_span     = 9
            }

            elements {
              element_id   = "bar-staffing-ratio"
              element_type = "VISUAL"
              column_index = 0
              column_span  = 36
              row_index    = 22
              row_span     = 9
            }
          }
        }
      }
    }
  }

  permissions {
    principal = local.admin_user_arn
    actions   = local.dashboard_owner_actions
  }

  tags = var.tags
}

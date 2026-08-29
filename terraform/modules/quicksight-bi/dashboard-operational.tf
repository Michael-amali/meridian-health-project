# Phase 7: the Operational / Clinical dashboard - the facility, department
# and shift level detail the RFP asks charge nurses and facility managers to
# run a shift from.
#
# Same structure as dashboard-executive.tf: dataset declarations, then one
# block per visual in screen order, then the grid. Two things are different
# here and both are deliberate:
#
#   1. A facility drop-down filters every visual on the sheet at once, which
#      is what "drill down by facility" means in practice. It filters across
#      all four datasets by column name, so one control moves the whole
#      sheet.
#   2. This is the dashboard row-level security actually matters for. A
#      facility manager opening it sees only their own facility's rows,
#      because every dataset it reads is scoped by the rules dataset in
#      rls.tf - the drop-down then only offers them the facility they can
#      already see.

resource "aws_quicksight_dashboard" "operational" {
  dashboard_id        = "meridian-operational-${var.env}"
  name                = "Meridian Operational & Clinical (${var.env})"
  version_description = "Phase 7 - facility, department and shift level operations"

  definition {
    data_set_identifiers_declarations {
      identifier   = "pharmacy_stock"
      data_set_arn = aws_quicksight_data_set.dashboard["pharmacy_stock"].arn
    }

    data_set_identifiers_declarations {
      identifier   = "bed_occupancy"
      data_set_arn = aws_quicksight_data_set.dashboard["bed_occupancy"].arn
    }

    data_set_identifiers_declarations {
      identifier   = "vitals_alerts"
      data_set_arn = aws_quicksight_data_set.dashboard["vitals_alerts"].arn
    }

    data_set_identifiers_declarations {
      identifier   = "staffing"
      data_set_arn = aws_quicksight_data_set.dashboard["staffing"].arn
    }

    filter_groups {
      filter_group_id = "facility-scope"
      status          = "ENABLED"

      # ALL_DATASETS: QuickSight matches the filter to a facility_name column
      # in every dataset on the sheet, so one control moves all four at once
      # instead of needing a separate filter per dataset.
      cross_dataset = "ALL_DATASETS"

      filters {
        category_filter {
          filter_id = "facility-name-filter"

          column {
            column_name         = "facility_name"
            data_set_identifier = "bed_occupancy"
          }

          configuration {
            filter_list_configuration {
              match_operator = "CONTAINS"

              # Nothing is filtered out until somebody picks a facility.
              select_all_options = "FILTER_ALL_VALUES"
            }
          }
        }
      }

      scope_configuration {
        selected_sheets {
          sheet_visual_scoping_configurations {
            sheet_id = "operational-detail"
            scope    = "ALL_VISUALS"
          }
        }
      }
    }

    sheets {
      sheet_id = "operational-detail"
      name     = "Operational detail"
      title    = "Facility operations - capacity, staffing, stock and alerts"

      filter_controls {
        dropdown {
          filter_control_id = "facility-control"
          source_filter_id  = "facility-name-filter"
          title             = "Facility"
          type              = "MULTI_SELECT"

          display_options {
            select_all_options {
              visibility = "VISIBLE"
            }

            # QuickSight fills these defaults in for any control that has a
            # title and echoes them back, so declaring them here is what stops
            # every future plan from showing the same phantom change.
            title_options {
              visibility = "VISIBLE"

              font_configuration {}
            }
          }
        }
      }

      # --- Top row: the four things that decide whether a shift is in
      # trouble right now ---

      visuals {
        kpi_visual {
          visual_id = "kpi-avg-occupancy"

          title {
            format_text {
              plain_text = "Average bed occupancy"
            }
          }

          chart_configuration {
            field_wells {
              values {
                numerical_measure_field {
                  field_id = "kpi-avg-occupancy.occupancy_rate"

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
      }

      visuals {
        kpi_visual {
          visual_id = "kpi-capacity-risk"

          # Counts department-days sitting at 90% occupancy or above - the
          # threshold is applied once, in datasets.tf, not here.
          title {
            format_text {
              plain_text = "Departments at capacity risk"
            }
          }

          chart_configuration {
            field_wells {
              values {
                numerical_measure_field {
                  field_id = "kpi-capacity-risk.at_capacity_risk"

                  column {
                    column_name         = "at_capacity_risk"
                    data_set_identifier = "bed_occupancy"
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

      visuals {
        kpi_visual {
          visual_id = "kpi-stockout-risk"

          title {
            format_text {
              plain_text = "Drugs at stockout risk"
            }
          }

          chart_configuration {
            field_wells {
              values {
                numerical_measure_field {
                  field_id = "kpi-stockout-risk.stockout_flag"

                  column {
                    column_name         = "stockout_flag"
                    data_set_identifier = "pharmacy_stock"
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

      visuals {
        kpi_visual {
          visual_id = "kpi-critical-alerts"

          title {
            format_text {
              plain_text = "Critical vitals alerts"
            }
          }

          chart_configuration {
            field_wells {
              values {
                categorical_measure_field {
                  field_id             = "kpi-critical-alerts.event_id"
                  aggregation_function = "COUNT"

                  column {
                    column_name         = "event_id"
                    data_set_identifier = "vitals_alerts"
                  }
                }
              }
            }
          }
        }
      }

      # --- Capacity and staffing by department and shift ---

      visuals {
        bar_chart_visual {
          visual_id = "bar-occupancy-by-department"

          title {
            format_text {
              plain_text = "Occupancy by department"
            }
          }

          chart_configuration {
            bars_arrangement = "CLUSTERED"
            orientation      = "HORIZONTAL"

            field_wells {
              bar_chart_aggregated_field_wells {
                category {
                  categorical_dimension_field {
                    field_id = "bar-occupancy-by-department.department"

                    column {
                      column_name         = "department"
                      data_set_identifier = "bed_occupancy"
                    }
                  }
                }

                colors {
                  categorical_dimension_field {
                    field_id = "bar-occupancy-by-department.facility_name"

                    column {
                      column_name         = "facility_name"
                      data_set_identifier = "bed_occupancy"
                    }
                  }
                }

                values {
                  numerical_measure_field {
                    field_id = "bar-occupancy-by-department.occupancy_rate"

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
        }
      }

      visuals {
        bar_chart_visual {
          visual_id = "bar-staff-by-shift"

          title {
            format_text {
              plain_text = "Rostered staff by shift and department"
            }
          }

          chart_configuration {
            bars_arrangement = "STACKED"
            orientation      = "VERTICAL"

            field_wells {
              bar_chart_aggregated_field_wells {
                category {
                  categorical_dimension_field {
                    field_id = "bar-staff-by-shift.shift_name"

                    column {
                      column_name         = "shift_name"
                      data_set_identifier = "staffing"
                    }
                  }
                }

                colors {
                  categorical_dimension_field {
                    field_id = "bar-staff-by-shift.department"

                    column {
                      column_name         = "department"
                      data_set_identifier = "staffing"
                    }
                  }
                }

                values {
                  numerical_measure_field {
                    field_id = "bar-staff-by-shift.staff_count"

                    column {
                      column_name         = "staff_count"
                      data_set_identifier = "staffing"
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
      }

      # --- Near-real-time clinical alerting ---

      visuals {
        line_chart_visual {
          visual_id = "line-alerts-over-time"

          title {
            format_text {
              plain_text = "Critical vitals alerts per hour"
            }
          }

          chart_configuration {
            type = "LINE"

            field_wells {
              line_chart_aggregated_field_wells {
                category {
                  date_dimension_field {
                    field_id         = "line-alerts-over-time.event_time"
                    hierarchy_id     = "line-alerts-over-time.event_time"
                    date_granularity = "HOUR"

                    column {
                      column_name         = "event_time"
                      data_set_identifier = "vitals_alerts"
                    }
                  }
                }

                colors {
                  categorical_dimension_field {
                    field_id = "line-alerts-over-time.facility_name"

                    column {
                      column_name         = "facility_name"
                      data_set_identifier = "vitals_alerts"
                    }
                  }
                }

                values {
                  categorical_measure_field {
                    field_id             = "line-alerts-over-time.event_id"
                    aggregation_function = "COUNT"

                    column {
                      column_name         = "event_id"
                      data_set_identifier = "vitals_alerts"
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
              hierarchy_id = "line-alerts-over-time.event_time"
            }
          }
        }
      }

      # --- The three worklists a manager actually acts on ---

      visuals {
        table_visual {
          visual_id = "table-staffing-pressure"

          title {
            format_text {
              plain_text = "Shifts by staffing pressure"
            }
          }

          chart_configuration {
            field_wells {
              table_aggregated_field_wells {
                group_by {
                  categorical_dimension_field {
                    field_id = "table-staffing-pressure.facility_name"

                    column {
                      column_name         = "facility_name"
                      data_set_identifier = "staffing"
                    }
                  }
                }

                group_by {
                  categorical_dimension_field {
                    field_id = "table-staffing-pressure.department"

                    column {
                      column_name         = "department"
                      data_set_identifier = "staffing"
                    }
                  }
                }

                group_by {
                  date_dimension_field {
                    field_id         = "table-staffing-pressure.shift_date"
                    date_granularity = "DAY"

                    column {
                      column_name         = "shift_date"
                      data_set_identifier = "staffing"
                    }
                  }
                }

                group_by {
                  categorical_dimension_field {
                    field_id = "table-staffing-pressure.shift_name"

                    column {
                      column_name         = "shift_name"
                      data_set_identifier = "staffing"
                    }
                  }
                }

                values {
                  numerical_measure_field {
                    field_id = "table-staffing-pressure.staff_count"

                    column {
                      column_name         = "staff_count"
                      data_set_identifier = "staffing"
                    }

                    aggregation_function {
                      simple_numerical_aggregation = "SUM"
                    }
                  }
                }

                values {
                  numerical_measure_field {
                    field_id = "table-staffing-pressure.occupied_beds"

                    column {
                      column_name         = "occupied_beds"
                      data_set_identifier = "staffing"
                    }

                    aggregation_function {
                      simple_numerical_aggregation = "SUM"
                    }
                  }
                }

                values {
                  numerical_measure_field {
                    field_id = "table-staffing-pressure.beds_per_staff"

                    column {
                      column_name         = "beds_per_staff"
                      data_set_identifier = "staffing"
                    }

                    aggregation_function {
                      simple_numerical_aggregation = "MAX"
                    }
                  }
                }
              }
            }
          }
        }
      }

      visuals {
        table_visual {
          visual_id = "table-stockout-risk"

          title {
            format_text {
              plain_text = "Pharmacy stock against reorder threshold"
            }
          }

          chart_configuration {
            field_wells {
              table_aggregated_field_wells {
                group_by {
                  categorical_dimension_field {
                    field_id = "table-stockout-risk.facility_name"

                    column {
                      column_name         = "facility_name"
                      data_set_identifier = "pharmacy_stock"
                    }
                  }
                }

                group_by {
                  categorical_dimension_field {
                    field_id = "table-stockout-risk.drug_name"

                    column {
                      column_name         = "drug_name"
                      data_set_identifier = "pharmacy_stock"
                    }
                  }
                }

                values {
                  numerical_measure_field {
                    field_id = "table-stockout-risk.current_stock"

                    column {
                      column_name         = "current_stock"
                      data_set_identifier = "pharmacy_stock"
                    }

                    aggregation_function {
                      simple_numerical_aggregation = "MIN"
                    }
                  }
                }

                values {
                  numerical_measure_field {
                    field_id = "table-stockout-risk.reorder_threshold"

                    column {
                      column_name         = "reorder_threshold"
                      data_set_identifier = "pharmacy_stock"
                    }

                    aggregation_function {
                      simple_numerical_aggregation = "MIN"
                    }
                  }
                }

                values {
                  numerical_measure_field {
                    field_id = "table-stockout-risk.stockout_flag"

                    column {
                      column_name         = "stockout_flag"
                      data_set_identifier = "pharmacy_stock"
                    }

                    aggregation_function {
                      simple_numerical_aggregation = "MAX"
                    }
                  }
                }
              }
            }
          }
        }
      }

      visuals {
        table_visual {
          visual_id = "table-recent-alerts"

          # Unaggregated on purpose: this is a clinical worklist, so each row
          # has to stay one real patient reading rather than a rollup.
          title {
            format_text {
              plain_text = "Critical vitals readings"
            }
          }

          chart_configuration {
            field_wells {
              table_unaggregated_field_wells {
                values {
                  field_id = "table-recent-alerts.event_time"

                  column {
                    column_name         = "event_time"
                    data_set_identifier = "vitals_alerts"
                  }
                }

                values {
                  field_id = "table-recent-alerts.facility_name"

                  column {
                    column_name         = "facility_name"
                    data_set_identifier = "vitals_alerts"
                  }
                }

                values {
                  field_id = "table-recent-alerts.patient_id"

                  column {
                    column_name         = "patient_id"
                    data_set_identifier = "vitals_alerts"
                  }
                }

                values {
                  field_id = "table-recent-alerts.heart_rate"

                  column {
                    column_name         = "heart_rate"
                    data_set_identifier = "vitals_alerts"
                  }
                }

                values {
                  field_id = "table-recent-alerts.spo2"

                  column {
                    column_name         = "spo2"
                    data_set_identifier = "vitals_alerts"
                  }
                }

                values {
                  field_id = "table-recent-alerts.systolic_bp"

                  column {
                    column_name         = "systolic_bp"
                    data_set_identifier = "vitals_alerts"
                  }
                }

                values {
                  field_id = "table-recent-alerts.temperature_c"

                  column {
                    column_name         = "temperature_c"
                    data_set_identifier = "vitals_alerts"
                  }
                }
              }
            }
          }
        }
      }

      # --- Placement ---

      # The control strip above the visuals has its own, much smaller grid
      # than the visual layout below: 12 columns wide, and QuickSight rejects
      # a span greater than 6 outright.
      sheet_control_layouts {
        configuration {
          grid_layout {
            elements {
              element_id   = "facility-control"
              element_type = "FILTER_CONTROL"
              column_index = 0
              column_span  = 4
              row_index    = 0
              row_span     = 1
            }
          }
        }
      }

      layouts {
        configuration {
          grid_layout {
            canvas_size_options {
              screen_canvas_size_options {
                resize_option = "RESPONSIVE"
              }
            }

            elements {
              element_id   = "kpi-avg-occupancy"
              element_type = "VISUAL"
              column_index = 0
              column_span  = 9
              row_index    = 0
              row_span     = 4
            }

            elements {
              element_id   = "kpi-capacity-risk"
              element_type = "VISUAL"
              column_index = 9
              column_span  = 9
              row_index    = 0
              row_span     = 4
            }

            elements {
              element_id   = "kpi-stockout-risk"
              element_type = "VISUAL"
              column_index = 18
              column_span  = 9
              row_index    = 0
              row_span     = 4
            }

            elements {
              element_id   = "kpi-critical-alerts"
              element_type = "VISUAL"
              column_index = 27
              column_span  = 9
              row_index    = 0
              row_span     = 4
            }

            elements {
              element_id   = "bar-occupancy-by-department"
              element_type = "VISUAL"
              column_index = 0
              column_span  = 18
              row_index    = 4
              row_span     = 9
            }

            elements {
              element_id   = "bar-staff-by-shift"
              element_type = "VISUAL"
              column_index = 18
              column_span  = 18
              row_index    = 4
              row_span     = 9
            }

            elements {
              element_id   = "line-alerts-over-time"
              element_type = "VISUAL"
              column_index = 0
              column_span  = 36
              row_index    = 13
              row_span     = 9
            }

            elements {
              element_id   = "table-staffing-pressure"
              element_type = "VISUAL"
              column_index = 0
              column_span  = 18
              row_index    = 22
              row_span     = 10
            }

            elements {
              element_id   = "table-stockout-risk"
              element_type = "VISUAL"
              column_index = 18
              column_span  = 18
              row_index    = 22
              row_span     = 10
            }

            elements {
              element_id   = "table-recent-alerts"
              element_type = "VISUAL"
              column_index = 0
              column_span  = 36
              row_index    = 32
              row_span     = 10
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

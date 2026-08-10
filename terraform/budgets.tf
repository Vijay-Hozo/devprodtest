/**
 * A billing budget per environment.
 *
 * Budgets live under the billing account, not the project, so this needs
 * `roles/billing.admin` on the billing account — a different permission from the
 * one that creates projects. That is the usual reason this file fails to apply.
 */

resource "google_billing_budget" "environment" {
  for_each = {
    for name, env in local.environments : name => env
    if env.monthly_budget != null
  }

  billing_account = var.billing_account_id
  display_name    = "budget-${each.value.project_id}"

  budget_filter {
    projects = ["projects/${google_project.environment[each.key].number}"]
    # Exclude credits so the budget tracks real spend.
    credit_types_treatment = "EXCLUDE_ALL_CREDITS"
  }

  amount {
    specified_amount {
      currency_code = var.budget_currency
      units         = tostring(each.value.monthly_budget)
    }
  }

  # Warn at 50% and 90% of actual spend...
  threshold_rules {
    threshold_percent = 0.5
    spend_basis       = "CURRENT_SPEND"
  }

  threshold_rules {
    threshold_percent = 0.9
    spend_basis       = "CURRENT_SPEND"
  }

  # ...and when the *forecast* says the month will overrun, which arrives early
  # enough to act on.
  threshold_rules {
    threshold_percent = 1.0
    spend_basis       = "FORECASTED_SPEND"
  }

  dynamic "all_updates_rule" {
    for_each = length(var.budget_notification_channels) > 0 ? [1] : []

    content {
      monitoring_notification_channels = var.budget_notification_channels
      disable_default_iam_recipients   = false
    }
  }
}

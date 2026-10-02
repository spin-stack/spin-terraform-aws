# What the installation may cost in a month: an AWS Budget over everything carrying its
# spin:installation tag - the machines, their disks, the buckets, the keys - with alerts at 80 % and
# 100 % of what it actually cost, and at 100 % of what AWS forecasts it will. Nothing is stopped
# when it is passed: a budget is a line someone is told about, and a machine or a key that stopped
# would be a workspace that does not start. The control plane reads it (ReadItsBudget in iam.tf)
# beside the bill itself, and shows both.
#
# The tag is read by the bill only once it is a cost allocation tag: bootstrap's
# cost_allocation_tags, after the installation has run for a day.

resource "aws_budgets_budget" "monthly" {
  count        = var.monthly_budget_usd == null ? 0 : 1
  name         = "${local.name}-monthly"
  budget_type  = "COST"
  limit_amount = tostring(var.monthly_budget_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  cost_filter {
    name   = "TagKeyValue"
    values = ["user:spin:installation$${local.name}"]
  }

  dynamic "notification" {
    for_each = length(var.budget_emails) == 0 ? [] : [
      { type = "ACTUAL", threshold = 80 },
      { type = "ACTUAL", threshold = 100 },
      { type = "FORECASTED", threshold = 100 },
    ]
    content {
      comparison_operator        = "GREATER_THAN"
      threshold                  = notification.value.threshold
      threshold_type             = "PERCENTAGE"
      notification_type          = notification.value.type
      subscriber_email_addresses = var.budget_emails
    }
  }

  tags = local.tags
}

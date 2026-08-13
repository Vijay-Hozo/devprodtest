/**
 * A DynamoDB global table: one logical table with a replica in each region,
 * writable in both, converging automatically.
 *
 * Modern DynamoDB expresses this as a `replica` block on a single resource
 * rather than the deprecated `aws_dynamodb_global_table`.
 */

resource "aws_dynamodb_table" "main" {
  provider = aws.primary

  name         = "${local.name_prefix}-app"
  billing_mode = var.dynamodb_billing_mode
  hash_key     = "pk"
  range_key    = "sk"

  # Global tables require streams with both images.
  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  attribute {
    name = "pk"
    type = "S"
  }

  attribute {
    name = "sk"
    type = "S"
  }

  # Provisioned capacity is ignored under PAY_PER_REQUEST, so only set it when
  # billing_mode is PROVISIONED.
  read_capacity  = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_read_capacity : null
  write_capacity = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_write_capacity : null

  replica {
    region_name            = var.secondary_region
    point_in_time_recovery = var.enable_point_in_time_recovery
  }

  point_in_time_recovery {
    enabled = var.enable_point_in_time_recovery
  }

  server_side_encryption {
    enabled = true
  }

  deletion_protection_enabled = var.enable_deletion_protection

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-app" })

  lifecycle {
    # Under PAY_PER_REQUEST, AWS reports capacity values Terraform did not set.
    ignore_changes = [read_capacity, write_capacity]
  }
}

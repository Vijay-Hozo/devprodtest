# ----------------------------------------------------------------------------
# Debug logging
# ----------------------------------------------------------------------------
# Terraform/OpenTofu does not support JavaScript-style console.log().
# If you need to "log everything", the closest equivalent is emitting output
# values during apply via a local-exec.
#
# This is intentionally controlled by var.debug_logging_enabled to avoid
# surprising stdout noise in CI.

resource "null_resource" "debug_log" {
  count = var.debug_logging_enabled ? 1 : 0

  triggers = {
    # Any change in these values will re-run the provisioner.
    debug_payload_sha1 = sha1(jsonencode({
      primary_region   = var.primary_region
      secondary_region = var.secondary_region

      networking = {
        primary_vpc_id    = aws_vpc.primary.id
        secondary_vpc_id  = aws_vpc.secondary.id
        primary_subnets   = aws_subnet.primary_private[*].id
        secondary_subnets = aws_subnet.secondary_private[*].id
        vpc_peering_id    = var.enable_vpc_peering ? aws_vpc_peering_connection.primary_to_secondary[0].id : null
      }

      storage = {
        primary_bucket_name   = aws_s3_bucket.primary.id
        secondary_bucket_name = aws_s3_bucket.secondary.id
        replication_role_arn  = aws_iam_role.replication.arn
      }

      database = {
        dynamodb_table_name = aws_dynamodb_table.main.name
        dynamodb_table_arn  = aws_dynamodb_table.main.arn
        dynamodb_stream_arn = aws_dynamodb_table.main.stream_arn
      }

      dns = {
        enabled     = var.enable_dns_failover
        record_name = var.enable_dns_failover ? var.dns_record_name : null
      }
    }))
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-lc"]
    command = <<-EOT
      echo "[debug] terraform outputs (summary)" 1>&2
      cat <<'JSON' 1>&2
${jsonencode({
  primary_region   = var.primary_region
  secondary_region = var.secondary_region

  primary_vpc_id   = aws_vpc.primary.id
  secondary_vpc_id = aws_vpc.secondary.id

  # "ALB DNS" / "CloudFront domain": this template doesn't create an ALB or
  # CloudFront distribution by default. If you have them elsewhere, set the
  # endpoints accordingly (typically ALB DNS names or a CloudFront domain).
  alb_dns_name         = var.primary_endpoint
  cloudfront_domain    = var.secondary_endpoint

  primary_subnet_ids     = aws_subnet.primary_private[*].id
  secondary_subnet_ids   = aws_subnet.secondary_private[*].id
  vpc_peering_connection_id = var.enable_vpc_peering ? aws_vpc_peering_connection.primary_to_secondary[0].id : null

  primary_bucket_name   = aws_s3_bucket.primary.id
  secondary_bucket_name = aws_s3_bucket.secondary.id
  replication_role_arn  = aws_iam_role.replication.arn

  dynamodb_table_name = aws_dynamodb_table.main.name
  dynamodb_table_arn  = aws_dynamodb_table.main.arn
  dynamodb_stream_arn = aws_dynamodb_table.main.stream_arn

  dns_record_name      = var.enable_dns_failover ? var.dns_record_name : null
  dns_failover_enabled = var.enable_dns_failover
})}
JSON
    EOT
  }
}

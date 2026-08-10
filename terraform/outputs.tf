output "primary_region" {
  description = "Region that normally serves traffic."
  value       = var.primary_region
}

output "secondary_region" {
  description = "Standby region."
  value       = var.secondary_region
}

# ── Networking ───────────────────────────────────────────────────────────────

output "primary_vpc_id" {
  description = "VPC id in the primary region."
  value       = aws_vpc.primary.id
}

output "secondary_vpc_id" {
  description = "VPC id in the secondary region."
  value       = aws_vpc.secondary.id
}

output "primary_subnet_ids" {
  description = "Private subnet ids in the primary region."
  value       = aws_subnet.primary_private[*].id
}

output "secondary_subnet_ids" {
  description = "Private subnet ids in the secondary region."
  value       = aws_subnet.secondary_private[*].id
}

output "vpc_peering_connection_id" {
  description = "Peering connection id, or null when peering is disabled."
  value       = var.enable_vpc_peering ? aws_vpc_peering_connection.primary_to_secondary[0].id : null
}

# ── Storage ──────────────────────────────────────────────────────────────────

output "primary_bucket_name" {
  description = "Bucket in the primary region. Write here; replication copies to the secondary."
  value       = aws_s3_bucket.primary.id
}

output "secondary_bucket_name" {
  description = "Replica bucket in the secondary region."
  value       = aws_s3_bucket.secondary.id
}

output "replication_role_arn" {
  description = "IAM role S3 assumes to replicate objects."
  value       = aws_iam_role.replication.arn
}

# ── Database ─────────────────────────────────────────────────────────────────

output "dynamodb_table_name" {
  description = "Name of the global table. The same name resolves in both regions."
  value       = aws_dynamodb_table.main.name
}

output "dynamodb_table_arn" {
  description = "ARN of the table in the primary region."
  value       = aws_dynamodb_table.main.arn
}

output "dynamodb_stream_arn" {
  description = "DynamoDB stream ARN — the mechanism global table replication uses."
  value       = aws_dynamodb_table.main.stream_arn
}

# ── DNS ──────────────────────────────────────────────────────────────────────

output "dns_record_name" {
  description = "Failover record name, or null when DNS failover is disabled."
  value       = var.enable_dns_failover ? var.dns_record_name : null
}

output "dns_failover_enabled" {
  description = "Whether Route 53 failover is active. False means nothing routes traffic between regions yet."
  value       = var.enable_dns_failover
}

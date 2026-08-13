/**
 * Data sources and locals only. Resources live in networking.tf, storage.tf,
 * database.tf and dns.tf.
 */

data "aws_availability_zones" "primary" {
  provider = aws.primary
  state    = "available"
}

# data "aws_availability_zones" "secondary" {
#   provider = aws.secondary
#   state    = "available"
# }

# Bucket names are globally unique across all of AWS, and the two replica
# buckets need distinct names.
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  name_prefix = "${var.project_name}-${var.environment}"

  primary_azs   = slice(data.aws_availability_zones.primary.names, 0, 2)
  secondary_azs = slice(data.aws_availability_zones.secondary.names, 0, 2)

  primary_bucket_name   = "${local.name_prefix}-${var.primary_region}-${random_id.suffix.hex}"
  secondary_bucket_name = "${local.name_prefix}-${var.secondary_region}-${random_id.suffix.hex}"

  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Template    = "aws-multi-region"
    },
    var.tags,
  )

  primary_tags   = merge(local.common_tags, { Region = var.primary_region, Role = "primary" })
  secondary_tags = merge(local.common_tags, { Region = var.secondary_region, Role = "secondary" })
}

# Non-overlapping CIDRs are a hard requirement if the two regions are ever
# peered or joined to a transit gateway.
check "non_overlapping_vpc_cidrs" {
  assert {
    condition = (
      cidrhost(var.primary_vpc_cidr, 0) != cidrhost(var.secondary_vpc_cidr, 0)
    )
    error_message = "primary_vpc_cidr and secondary_vpc_cidr must not be the same range — overlapping CIDRs cannot be peered."
  }
}

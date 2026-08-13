/**
 * One VPC per region. Deliberately duplicated rather than factored into a
 * module: the two blocks differ only by provider, and seeing both makes the
 * provider aliasing obvious — which is the whole point of this template.
 */

# ── Primary region ───────────────────────────────────────────────────────────

resource "aws_vpc" "primary" {
  provider = aws.primary

  cidr_block           = var.primary_vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.primary_tags, { Name = "${local.name_prefix}-primary-vpc" })
}

resource "aws_subnet" "primary_private" {
  provider = aws.primary
  count    = 2

  vpc_id            = aws_vpc.primary.id
  cidr_block        = cidrsubnet(var.primary_vpc_cidr, 8, count.index)
  availability_zone = local.primary_azs[count.index]

  tags = merge(local.primary_tags, {
    Name = "${local.name_prefix}-primary-private-${count.index + 1}"
    Tier = "private"
  })
}

resource "aws_security_group" "primary_app" {
  provider = aws.primary

  name_prefix = "${local.name_prefix}-primary-app-"
  description = "Application tier in the primary region"
  vpc_id      = aws_vpc.primary.id

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(local.primary_tags, { Name = "${local.name_prefix}-primary-app-sg" })
}

# ── Secondary region ─────────────────────────────────────────────────────────

resource "aws_vpc" "secondary" {
  provider = aws.secondary

  cidr_block           = var.secondary_vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.secondary_tags, { Name = "${local.name_prefix}-secondary-vpc" })
}

resource "aws_subnet" "secondary_private" {
  provider = aws.secondary
  count    = 2

  vpc_id            = aws_vpc.secondary.id
  cidr_block        = cidrsubnet(var.secondary_vpc_cidr, 8, count.index)
  availability_zone = local.secondary_azs[count.index]

  tags = merge(local.secondary_tags, {
    Name = "${local.name_prefix}-secondary-private-${count.index + 1}"
    Tier = "private"
  })
}

resource "aws_security_group" "secondary_app" {
  provider = aws.secondary

  name_prefix = "${local.name_prefix}-secondary-app-"
  description = "Application tier in the secondary region"
  vpc_id      = aws_vpc.secondary.id

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(local.secondary_tags, { Name = "${local.name_prefix}-secondary-app-sg" })
}

# ── Cross-region connectivity ────────────────────────────────────────────────

# Peering is opt-in: it is only needed if workloads in one region must reach
# private addresses in the other. S3 replication and DynamoDB global tables
# replicate over the AWS backbone and do NOT require it.
resource "aws_vpc_peering_connection" "primary_to_secondary" {
  provider = aws.primary
  count    = var.enable_vpc_peering ? 1 : 0

  vpc_id      = aws_vpc.primary.id
  peer_vpc_id = aws_vpc.secondary.id
  peer_region = var.secondary_region
  auto_accept = false

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-peering" })
}

# A cross-region peering must be accepted from the other side, which means a
# second resource using the secondary provider.
resource "aws_vpc_peering_connection_accepter" "secondary" {
  provider = aws.secondary
  count    = var.enable_vpc_peering ? 1 : 0

  vpc_peering_connection_id = aws_vpc_peering_connection.primary_to_secondary[0].id
  auto_accept               = true

  tags = merge(local.secondary_tags, { Name = "${local.name_prefix}-peering-accepter" })
}

/**
 * S3 with cross-region replication. Objects written to the primary bucket are
 * copied to the secondary automatically, over the AWS backbone.
 *
 * Replication requires versioning on BOTH buckets — it is the mechanism CRR
 * uses to track what needs copying.
 */

# ── Buckets ──────────────────────────────────────────────────────────────────

resource "aws_s3_bucket" "primary" {
  provider = aws.primary

  bucket        = local.primary_bucket_name
  force_destroy = var.force_destroy

  tags = merge(local.primary_tags, { Name = local.primary_bucket_name })
}

resource "aws_s3_bucket" "secondary" {
  provider = aws.secondary

  bucket        = local.secondary_bucket_name
  force_destroy = var.force_destroy

  tags = merge(local.secondary_tags, { Name = local.secondary_bucket_name })
}

# ── Versioning (mandatory for replication) ───────────────────────────────────

resource "aws_s3_bucket_versioning" "primary" {
  provider = aws.primary
  bucket   = aws_s3_bucket.primary.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_versioning" "secondary" {
  provider = aws.secondary
  bucket   = aws_s3_bucket.secondary.id

  versioning_configuration {
    status = "Enabled"
  }
}

# ── Access control ───────────────────────────────────────────────────────────

resource "aws_s3_bucket_public_access_block" "primary" {
  provider = aws.primary
  bucket   = aws_s3_bucket.primary.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "secondary" {
  provider = aws.secondary
  bucket   = aws_s3_bucket.secondary.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "primary" {
  provider = aws.primary
  bucket   = aws_s3_bucket.primary.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }

    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "secondary" {
  provider = aws.secondary
  bucket   = aws_s3_bucket.secondary.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }

    bucket_key_enabled = true
  }
}

# ── Replication role ─────────────────────────────────────────────────────────

data "aws_iam_policy_document" "replication_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "replication" {
  provider = aws.primary

  name_prefix        = "${local.name_prefix}-s3-repl-"
  assume_role_policy = data.aws_iam_policy_document.replication_assume_role.json

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-s3-replication" })
}

# Read + version metadata on the source, write on the destination. Nothing more.
data "aws_iam_policy_document" "replication" {
  statement {
    sid    = "ReadSourceBucket"
    effect = "Allow"

    actions = [
      "s3:GetReplicationConfiguration",
      "s3:ListBucket",
    ]

    resources = [aws_s3_bucket.primary.arn]
  }

  statement {
    sid    = "ReadSourceObjects"
    effect = "Allow"

    actions = [
      "s3:GetObjectVersionForReplication",
      "s3:GetObjectVersionAcl",
      "s3:GetObjectVersionTagging",
    ]

    resources = ["${aws_s3_bucket.primary.arn}/*"]
  }

  statement {
    sid    = "WriteDestinationObjects"
    effect = "Allow"

    actions = [
      "s3:ReplicateObject",
      "s3:ReplicateDelete",
      "s3:ReplicateTags",
    ]

    resources = ["${aws_s3_bucket.secondary.arn}/*"]
  }
}

resource "aws_iam_policy" "replication" {
  provider = aws.primary

  name_prefix = "${local.name_prefix}-s3-repl-"
  policy      = data.aws_iam_policy_document.replication.json
}

resource "aws_iam_role_policy_attachment" "replication" {
  provider = aws.primary

  role       = aws_iam_role.replication.name
  policy_arn = aws_iam_policy.replication.arn
}

# ── Replication rule ─────────────────────────────────────────────────────────

resource "aws_s3_bucket_replication_configuration" "primary_to_secondary" {
  provider = aws.primary

  bucket = aws_s3_bucket.primary.id
  role   = aws_iam_role.replication.arn

  rule {
    id       = "replicate-all-to-secondary"
    status   = "Enabled"
    priority = 0

    filter {}

    # Required when filter is present: replicate deletes of the current version
    # as delete markers rather than silently diverging.
    delete_marker_replication {
      status = "Enabled"
    }

    destination {
      bucket        = aws_s3_bucket.secondary.arn
      storage_class = var.replica_storage_class

      # Surfaces replication lag as a CloudWatch metric so RPO is measurable
      # rather than assumed.
      metrics {
        status = "Enabled"

        event_threshold {
          minutes = 15
        }
      }
    }
  }

  # Replication cannot be configured before versioning is active on the source.
  depends_on = [
    aws_s3_bucket_versioning.primary,
    aws_s3_bucket_versioning.secondary,
  ]
}

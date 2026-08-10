/**
 * Route 53 health checks and failover records — how traffic actually moves
 * between regions.
 *
 * Opt-in, because it needs a hosted zone you already own. Without it the two
 * regions exist but nothing routes between them.
 *
 * Route 53 is global; its API lives in us-east-1, hence `provider = aws.global`.
 */

resource "aws_route53_health_check" "primary" {
  provider = aws.global
  count    = var.enable_dns_failover ? 1 : 0

  fqdn              = var.primary_endpoint
  port              = 443
  type              = "HTTPS"
  resource_path     = var.health_check_path
  failure_threshold = 3
  request_interval  = 30

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-primary-health" })
}

resource "aws_route53_health_check" "secondary" {
  provider = aws.global
  count    = var.enable_dns_failover ? 1 : 0

  fqdn              = var.secondary_endpoint
  port              = 443
  type              = "HTTPS"
  resource_path     = var.health_check_path
  failure_threshold = 3
  request_interval  = 30

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-secondary-health" })
}

# PRIMARY answers while its health check passes; SECONDARY takes over when it
# fails. Failover is as fast as DNS TTL plus the health check threshold — with
# the defaults here, roughly 90 seconds plus 60.
resource "aws_route53_record" "primary" {
  provider = aws.global
  count    = var.enable_dns_failover ? 1 : 0

  zone_id = var.hosted_zone_id
  name    = var.dns_record_name
  type    = "CNAME"
  ttl     = var.dns_ttl
  records = [var.primary_endpoint]

  set_identifier  = "primary"
  health_check_id = aws_route53_health_check.primary[0].id

  failover_routing_policy {
    type = "PRIMARY"
  }
}

resource "aws_route53_record" "secondary" {
  provider = aws.global
  count    = var.enable_dns_failover ? 1 : 0

  zone_id = var.hosted_zone_id
  name    = var.dns_record_name
  type    = "CNAME"
  ttl     = var.dns_ttl
  records = [var.secondary_endpoint]

  set_identifier  = "secondary"
  health_check_id = aws_route53_health_check.secondary[0].id

  failover_routing_policy {
    type = "SECONDARY"
  }
}

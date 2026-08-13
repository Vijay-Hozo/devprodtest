# Multi-Region Architecture

Two regions, with data replicating between them and DNS failover moving traffic
when one goes down.

```
                    ┌──────────────────────────┐
                    │  Route 53 failover        │
                    │  app.example.com          │
                    └───────┬──────────┬────────┘
                     PRIMARY│          │SECONDARY
                    ┌───────▼──┐   ┌───▼───────┐
                    │ us-east-1│   │ us-west-2 │
                    │  VPC     │   │  VPC      │
                    │  10.0/16 │   │  10.1/16  │
                    └───┬──────┘   └──────┬────┘
                        │                 │
      S3 bucket ────────┼── CRR ──────────┼──► S3 replica
                        │                 │
      DynamoDB ◄────────┴─ global table ──┴──► DynamoDB
                          (writable both ends)
```

## How the provider aliasing works

This is the mechanism that makes multi-region possible, and it's the main thing
to understand before editing:

```hcl
provider "aws" { region = var.primary_region }                      # default
provider "aws" { alias = "primary"   region = var.primary_region }
provider "aws" { alias = "secondary" region = var.secondary_region }
provider "aws" { alias = "global"    region = "us-east-1" }
```

Every resource declares which one it uses:

```hcl
resource "aws_vpc" "secondary" {
  provider = aws.secondary
  # ...
}
```

**Terraform cannot loop a provider block** — you cannot `for_each` over a list of
regions. That is why this template handles exactly two regions, and why adding a
third means adding another alias and another set of resources. It is also why
`networking.tf` deliberately repeats itself rather than hiding the duplication in
a module: seeing both blocks makes the aliasing obvious.

`aws.global` exists because Route 53 and CloudFront are global services whose
APIs live in `us-east-1`, regardless of where your workload runs.

## What it creates

**`networking.tf`** — one VPC per region, two private subnets each (carved with
`cidrsubnet()`), a security group each, and optional cross-region VPC peering.

**`storage.tf`** — two S3 buckets with versioning, public access blocked and
encryption, plus a least-privilege IAM role and a replication rule copying the
primary to the secondary. Replication metrics are on, so lag is measurable.

**`database.tf`** — a DynamoDB global table: one resource with a `replica` block,
writable in **both** regions and converging automatically.

**`dns.tf`** — Route 53 health checks on both endpoints and a PRIMARY/SECONDARY
failover record pair.

## Getting started

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # then edit
terraform init
terraform validate
terraform plan
terraform apply
```

DNS failover is **off by default** because it needs a hosted zone you already own
and endpoints that exist. Until you enable it, the two regions are stood up but
nothing routes between them:

```hcl
enable_dns_failover = true
hosted_zone_id      = "Z0123456789ABCDEFGHIJ"
dns_record_name     = "app.example.com"
primary_endpoint    = "primary-alb-123.us-east-1.elb.amazonaws.com"
secondary_endpoint  = "secondary-alb-456.us-west-2.elb.amazonaws.com"
```

## What this gives you, and what it doesn't

| | |
|---|---|
| **S3 RPO** | Typically seconds to minutes. CRR is asynchronous — a region lost mid-replication loses in-flight objects. The 15-minute metrics threshold makes lag visible. |
| **DynamoDB RPO** | Sub-second, and writable in both regions. Conflicts resolve last-writer-wins, so design for idempotency. |
| **RTO** | DNS TTL (60s) + health check threshold (3 × 30s) ≈ **90-150 seconds**. |

**Not included, and needed for a real DR posture:**

- **Compute.** The VPCs and security groups exist but nothing runs in them. Add
  an ASG or ECS service per region — with `provider = aws.primary` /
  `aws.secondary`.
- **RDS cross-region read replicas**, if you need a relational database. DynamoDB
  global tables are the easy path; RDS is not.
- **A tested failover runbook.** Untested DR is not DR.

## Notes

- **Versioning is mandatory for replication** on both buckets — it is how CRR
  tracks what to copy. Do not disable it.
- **Replication is not retroactive.** Only objects written *after* the rule is
  created are copied. Use S3 Batch Replication for pre-existing data.
- **`delete_marker_replication` is enabled.** Deletes propagate as delete
  markers. If you would rather the replica retain deleted objects, disable it —
  but then the buckets diverge.
- **Peering is off by default.** Neither S3 replication nor DynamoDB global tables
  need it; they use the AWS backbone. Turn it on only for private cross-region
  traffic.
- **A cross-region peering needs both sides**, which is why there is both a
  `aws_vpc_peering_connection` (primary) and an `aws_vpc_peering_connection_accepter`
  (secondary).
- `ignore_changes = [read_capacity, write_capacity]` on the table: under
  `PAY_PER_REQUEST`, AWS reports capacity values Terraform never set, which would
  otherwise show as permanent drift.
- The `check` block asserts the two VPC CIDRs differ — a cheap guard against a
  copy-paste that would make peering impossible.

## Cost

Multi-region roughly doubles infrastructure cost, and adds:

- **Cross-region replication transfer** — ~$0.02/GB out of the primary region.
  This is usually the surprise line.
- **DynamoDB replicated writes** — billed as write units in *both* regions.
- **Route 53 health checks** — ~$0.50/month each.

At defaults with no compute, the standing cost is small (two empty VPCs are free;
S3 and DynamoDB are usage-billed). The cost arrives with traffic and data volume.

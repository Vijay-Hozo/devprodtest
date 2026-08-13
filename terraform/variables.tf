variable "project_name" {
  description = "Short project name used to prefix every resource."
  type        = string
  default     = "synfra-app"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,11}$", var.project_name))
    error_message = "project_name must be 2-12 characters of lowercase letters, digits or hyphens, and start with a letter or digit."
  }
}

variable "environment" {
  description = "Deployment environment. Also used in resource names."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "test", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, test, staging, prod."
  }
}

variable "tags" {
  description = "Extra tags merged onto every resource."
  type        = map(string)
  default     = {}
}

variable "debug_logging_enabled" {
  description = "When true, emits a JSON summary of key values to stderr during apply via local-exec (Terraform/OpenTofu has no console.log())."
  type        = bool
  default     = false
}

# ── Regions ──────────────────────────────────────────────────────────────────

variable "primary_region" {
  description = "Region that normally serves traffic. Also the default provider's region."
  type        = string
  default     = "us-east-1"
}

variable "secondary_region" {
  description = "Standby (or second active) region. Must differ from primary_region."
  type        = string
  default     = "us-west-2"
}

# ── Networking ───────────────────────────────────────────────────────────────

variable "primary_vpc_cidr" {
  description = "CIDR for the primary region's VPC. Must not overlap the secondary."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.primary_vpc_cidr, 0))
    error_message = "primary_vpc_cidr must be a valid IPv4 CIDR block."
  }
}

variable "secondary_vpc_cidr" {
  description = "CIDR for the secondary region's VPC. Must not overlap the primary — overlapping ranges cannot be peered."
  type        = string
  default     = "10.1.0.0/16"

  validation {
    condition     = can(cidrhost(var.secondary_vpc_cidr, 0))
    error_message = "secondary_vpc_cidr must be a valid IPv4 CIDR block."
  }
}

variable "enable_vpc_peering" {
  description = "Peer the two VPCs. Only needed if workloads must reach private addresses across regions — S3 replication and DynamoDB global tables do not require it."
  type        = bool
  default     = false
}

# ── Storage ──────────────────────────────────────────────────────────────────

variable "replica_storage_class" {
  description = "Storage class for replicated objects. STANDARD_IA cuts standby cost; use STANDARD for active-active."
  type        = string
  default     = "STANDARD_IA"

  validation {
    condition = contains(
      ["STANDARD", "STANDARD_IA", "ONEZONE_IA", "INTELLIGENT_TIERING", "GLACIER_IR"],
      var.replica_storage_class,
    )
    error_message = "replica_storage_class must be a valid S3 storage class."
  }
}

variable "force_destroy" {
  description = "Allow `terraform destroy` to delete buckets that still hold objects. Leave false for anything you care about."
  type        = bool
  default     = false
}

# ── Database ─────────────────────────────────────────────────────────────────

variable "dynamodb_billing_mode" {
  description = "PAY_PER_REQUEST or PROVISIONED. On-demand is easier to reason about across regions."
  type        = string
  default     = "PAY_PER_REQUEST"

  validation {
    condition     = contains(["PAY_PER_REQUEST", "PROVISIONED"], var.dynamodb_billing_mode)
    error_message = "dynamodb_billing_mode must be PAY_PER_REQUEST or PROVISIONED."
  }
}

variable "dynamodb_read_capacity" {
  description = "Read capacity units. Ignored unless dynamodb_billing_mode is PROVISIONED."
  type        = number
  default     = 5
}

variable "dynamodb_write_capacity" {
  description = "Write capacity units. Ignored unless dynamodb_billing_mode is PROVISIONED."
  type        = number
  default     = 5
}

variable "enable_point_in_time_recovery" {
  description = "Continuous backups with 35-day restore, in both regions."
  type        = bool
  default     = true
}

variable "enable_deletion_protection" {
  description = "Block accidental deletion of the table."
  type        = bool
  default     = false
}

# ── DNS failover ─────────────────────────────────────────────────────────────

variable "enable_dns_failover" {
  description = "Create Route 53 health checks and failover records. Requires hosted_zone_id and both endpoints. Without this, nothing routes traffic between the regions."
  type        = bool
  default     = false
}

variable "hosted_zone_id" {
  description = "Route 53 hosted zone to create the failover records in. Required when enable_dns_failover is true."
  type        = string
  default     = null
}

variable "dns_record_name" {
  description = "Fully-qualified record name, e.g. app.example.com."
  type        = string
  default     = null
}

variable "primary_endpoint" {
  description = "Hostname the primary region serves on — typically a load balancer DNS name."
  type        = string
  default     = null
}

variable "secondary_endpoint" {
  description = "Hostname the secondary region serves on."
  type        = string
  default     = null
}

variable "health_check_path" {
  description = "Path the Route 53 health checks request. Must return 2xx/3xx only when the region can actually serve traffic."
  type        = string
  default     = "/health"
}

variable "dns_ttl" {
  description = "TTL in seconds for the failover records. Lower means faster failover but more DNS queries."
  type        = number
  default     = 60
}

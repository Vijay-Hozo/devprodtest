# ── Organisation & billing ───────────────────────────────────────────────────

variable "billing_account_id" {
  description = "Billing account to attach every project to, e.g. 012345-6789AB-CDEF01. Needs roles/billing.user to attach, and roles/billing.admin to create budgets."
  type        = string

  validation {
    condition     = can(regex("^[A-Z0-9]{6}-[A-Z0-9]{6}-[A-Z0-9]{6}$", var.billing_account_id))
    error_message = "billing_account_id must look like 012345-6789AB-CDEF01."
  }
}

variable "folder_id" {
  description = "Folder to create the projects under, digits only. Preferred over org_id — a folder scopes IAM and policy to just these environments. Leave null to create at organization level."
  type        = string
  default     = null

  validation {
    condition     = var.folder_id == null || can(regex("^[0-9]+$", var.folder_id))
    error_message = "folder_id must be digits only — strip any 'folders/' prefix."
  }
}

variable "org_id" {
  description = "Organization to create the projects under. Used only when folder_id is null."
  type        = string
  default     = null

  validation {
    condition     = var.org_id == null || can(regex("^[0-9]+$", var.org_id))
    error_message = "org_id must be digits only."
  }
}

# ── Naming ───────────────────────────────────────────────────────────────────

variable "project_prefix" {
  description = "Prefix for generated project IDs. Kept short — project IDs are capped at 30 characters and a random suffix is appended."
  type        = string
  default     = "synfra-app"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{3,15}$", var.project_prefix))
    error_message = "project_prefix must be 4-16 characters, start with a lowercase letter, and contain only lowercase letters, digits or hyphens."
  }
}

variable "display_name_prefix" {
  description = "Human-readable prefix for project display names."
  type        = string
  default     = "Synfra App"
}

variable "region" {
  description = "Default region for any environment that does not set its own."
  type        = string
  default     = "us-central1"
}

variable "labels" {
  description = "Labels merged onto every project."
  type        = map(string)
  default     = {}
}

# ── The environment map ──────────────────────────────────────────────────────

variable "environments" {
  description = <<-EOT
    Every environment, keyed by name. Adding an entry creates a complete project;
    removing one deletes just that project.

      region         — region, or null to use var.region
      subnet_cidr    — subnet range. Must be distinct across environments.
      is_production  — forces deletion_policy PREVENT and full flow sampling
      monthly_budget — budget in var.budget_currency, or null for no budget
      extra_apis     — APIs beyond common_apis for this environment only
      admin_members  — principals granted roles/editor
      viewer_members — principals granted roles/viewer
      labels         — extra labels for this environment only
  EOT

  type = map(object({
    region         = optional(string, null)
    subnet_cidr    = string
    is_production  = optional(bool, false)
    monthly_budget = optional(number, null)
    extra_apis     = optional(list(string), [])
    admin_members  = optional(list(string), [])
    viewer_members = optional(list(string), [])
    labels         = optional(map(string), {})
  }))

  default = {
    dev = {
      subnet_cidr    = "10.10.0.0/20"
      is_production  = false
      monthly_budget = 100
    }

    test = {
      subnet_cidr    = "10.20.0.0/20"
      is_production  = false
      monthly_budget = 200
    }

    prod = {
      subnet_cidr    = "10.30.0.0/20"
      is_production  = true
      monthly_budget = 2000
    }
  }

  validation {
    condition     = length(var.environments) > 0
    error_message = "Define at least one environment."
  }

  validation {
    condition = alltrue([
      for name, _ in var.environments : can(regex("^[a-z0-9]{2,10}$", name))
    ])
    error_message = "Environment names must be 2-10 lowercase alphanumeric characters — they become part of the project ID."
  }

  validation {
    condition = alltrue([
      for _, env in var.environments : can(cidrhost(env.subnet_cidr, 0))
    ])
    error_message = "Every subnet_cidr must be a valid IPv4 CIDR block."
  }
}

variable "non_production_deletion_policy" {
  description = "Deletion policy for non-production projects. DELETE allows `terraform destroy`; PREVENT blocks it. Production is always PREVENT."
  type        = string
  default     = "DELETE"

  validation {
    condition     = contains(["DELETE", "PREVENT", "ABANDON"], var.non_production_deletion_policy)
    error_message = "non_production_deletion_policy must be DELETE, PREVENT or ABANDON."
  }
}

# ── APIs ─────────────────────────────────────────────────────────────────────

variable "common_apis" {
  description = "APIs enabled in every environment. Nothing on GCP works until its API is on, and enablement is per-project."
  type        = list(string)
  default = [
    "compute.googleapis.com",
    "iam.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "secretmanager.googleapis.com",
    "storage.googleapis.com",
    "cloudresourcemanager.googleapis.com",
  ]
}

# ── Budgets ──────────────────────────────────────────────────────────────────

variable "budget_currency" {
  description = "Currency code for budget amounts. Must match the billing account's currency."
  type        = string
  default     = "USD"
}

variable "budget_notification_channels" {
  description = "Cloud Monitoring notification channel IDs to alert. Billing account admins are notified regardless."
  type        = list(string)
  default     = []
}

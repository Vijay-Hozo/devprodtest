/**
 * Data sources and locals only. Resources live in projects.tf, apis.tf,
 * network.tf and budgets.tf.
 *
 * Everything is driven by `var.environments`. On GCP a project is the real
 * isolation boundary — quotas, IAM, billing and API enablement are all
 * per-project — so one project per environment is stronger separation than
 * Azure's resource groups or AWS's tags.
 */

# Project IDs are globally unique across all of Google Cloud, so a suffix keeps
# `synfra-app-dev` from colliding with someone else's.
resource "random_id" "project_suffix" {
  byte_length = 3
}

locals {
  environments = {
    for name, cfg in var.environments : name => merge(cfg, {
      # Project IDs are capped at 30 characters.
      project_id   = substr("${var.project_prefix}-${name}-${random_id.project_suffix.hex}", 0, 30)
      project_name = "${var.display_name_prefix} ${upper(name)}"

      labels = merge(
        {
          environment = name
          managed_by  = "terraform"
          template    = "gcp-environments"
          criticality = cfg.is_production ? "high" : "low"
        },
        var.labels,
        cfg.labels,
      )
    })
  }

  # Flatten environment × API so one resource enables every service everywhere.
  project_apis = merge([
    for env_name, env in local.environments : {
      for api in distinct(concat(var.common_apis, env.extra_apis)) :
      "${env_name}/${api}" => {
        environment = env_name
        api         = api
      }
    }
  ]...)

  production_environments = [
    for name, env in local.environments : name if env.is_production
  ]
}

# Overlapping ranges cannot be peered to a hub or joined by a VPN later.
check "unique_subnet_ranges" {
  assert {
    condition = length(distinct([
      for env in local.environments : env.subnet_cidr
    ])) == length(local.environments)
    error_message = "Every environment needs a distinct subnet_cidr — overlapping ranges cannot be peered."
  }
}

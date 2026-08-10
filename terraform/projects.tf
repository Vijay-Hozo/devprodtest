/**
 * One project per environment, under an optional folder.
 *
 * `for_each` over a map rather than `count` over a list, so removing "test"
 * doesn't renumber — and therefore delete and recreate — the others. Recreating
 * a project is not a small thing: the ID is reserved for 30 days.
 */

resource "google_project" "environment" {
  for_each = local.environments

  name       = each.value.project_name
  project_id = each.value.project_id

  # A project must be under either a folder or an organization.
  folder_id = var.folder_id
  org_id    = var.folder_id == null ? var.org_id : null

  billing_account = var.billing_account_id

  # Google's default network creates a subnet in every region with permissive
  # firewall rules. network.tf builds a custom-mode VPC instead.
  auto_create_network = false

  labels = each.value.labels

  # Deleting a project is a 30-day soft delete during which the ID cannot be
  # reused — worth making deliberate.
  deletion_policy = each.value.is_production ? "PREVENT" : var.non_production_deletion_policy
}

# ── Project-level IAM ────────────────────────────────────────────────────────

# Grants keyed by environment so a dev team can own dev without touching prod.
resource "google_project_iam_member" "environment_admins" {
  for_each = {
    for pair in flatten([
      for env_name, env in local.environments : [
        for member in env.admin_members : {
          key         = "${env_name}/${member}"
          environment = env_name
          member      = member
        }
      ]
    ]) : pair.key => pair
  }

  project = google_project.environment[each.value.environment].project_id
  role    = "roles/editor"
  member  = each.value.member
}

resource "google_project_iam_member" "environment_viewers" {
  for_each = {
    for pair in flatten([
      for env_name, env in local.environments : [
        for member in env.viewer_members : {
          key         = "${env_name}/${member}"
          environment = env_name
          member      = member
        }
      ]
    ]) : pair.key => pair
  }

  project = google_project.environment[each.value.environment].project_id
  role    = "roles/viewer"
  member  = each.value.member
}

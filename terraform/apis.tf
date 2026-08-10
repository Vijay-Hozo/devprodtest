/**
 * API enablement, per project.
 *
 * On GCP nothing works until its API is enabled, and enablement is per-project —
 * which is why a new project appears broken until this runs. Enabling here means
 * every environment starts with the same baseline.
 */

resource "google_project_service" "environment" {
  for_each = local.project_apis

  project = google_project.environment[each.value.environment].project_id
  service = each.value.api

  # Leave the API on if it is removed from the config: disabling one can break
  # resources that are still running, and Terraform cannot tell.
  disable_on_destroy         = false
  disable_dependent_services = false
}

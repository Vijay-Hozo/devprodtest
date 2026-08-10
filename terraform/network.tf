/**
 * A custom-mode VPC per project, with one subnet and a deny-by-default firewall.
 *
 * `auto_create_network = false` on the project means we build this deliberately
 * rather than inheriting Google's default network, which spans every region and
 * ships permissive firewall rules.
 */

resource "google_compute_network" "environment" {
  for_each = local.environments

  name                    = "vpc-${each.key}"
  project                 = google_project.environment[each.key].project_id
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"

  # The compute API has to be on before a network can be created.
  depends_on = [google_project_service.environment]
}

resource "google_compute_subnetwork" "environment" {
  for_each = local.environments

  name          = "snet-${each.key}"
  project       = google_project.environment[each.key].project_id
  region        = coalesce(each.value.region, var.region)
  network       = google_compute_network.environment[each.key].id
  ip_cidr_range = each.value.subnet_cidr

  private_ip_google_access = true

  log_config {
    aggregation_interval = "INTERVAL_10_MIN"
    # Production keeps full sampling; lower environments halve the log volume.
    flow_sampling = each.value.is_production ? 1.0 : 0.5
    metadata      = "INCLUDE_ALL_METADATA"
  }
}

# ── Baseline firewall ────────────────────────────────────────────────────────

resource "google_compute_firewall" "allow_internal" {
  for_each = local.environments

  name    = "fw-${each.key}-allow-internal"
  project = google_project.environment[each.key].project_id
  network = google_compute_network.environment[each.key].id

  description   = "Traffic within the environment's own subnet"
  direction     = "INGRESS"
  priority      = 1000
  source_ranges = [each.value.subnet_cidr]

  allow {
    protocol = "all"
  }
}

# IAP's fixed range. SSH is tunnelled, so port 22 is never open to the internet.
resource "google_compute_firewall" "allow_iap" {
  for_each = local.environments

  name    = "fw-${each.key}-allow-iap"
  project = google_project.environment[each.key].project_id
  network = google_compute_network.environment[each.key].id

  description   = "SSH and RDP via Identity-Aware Proxy"
  direction     = "INGRESS"
  priority      = 1000
  source_ranges = ["35.235.240.0/20"]

  allow {
    protocol = "tcp"
    ports    = ["22", "3389"]
  }
}

resource "google_compute_firewall" "deny_all_ingress" {
  for_each = local.environments

  name    = "fw-${each.key}-deny-ingress"
  project = google_project.environment[each.key].project_id
  network = google_compute_network.environment[each.key].id

  description   = "Deny everything not explicitly allowed above"
  direction     = "INGRESS"
  priority      = 65534
  source_ranges = ["0.0.0.0/0"]

  deny {
    protocol = "all"
  }
}

output "environment_names" {
  description = "Environments that were created."
  value       = sort(keys(local.environments))
}

output "project_ids" {
  description = "Project ID per environment — what gcloud and Terraform providers need."
  value       = { for name, p in google_project.environment : name => p.project_id }
}

output "project_numbers" {
  description = "Project number per environment — what IAM bindings and budget filters need."
  value       = { for name, p in google_project.environment : name => p.number }
}

output "project_names" {
  description = "Display name per environment."
  value       = { for name, p in google_project.environment : name => p.name }
}

output "network_ids" {
  description = "VPC network ID per environment."
  value       = { for name, n in google_compute_network.environment : name => n.id }
}

output "subnet_ids" {
  description = "Subnet ID per environment."
  value       = { for name, s in google_compute_subnetwork.environment : name => s.id }
}

output "subnet_cidrs" {
  description = "Subnet range per environment. Distinct by design, so they can be peered to a hub."
  value       = { for name, env in local.environments : name => env.subnet_cidr }
}

output "regions" {
  description = "Region each environment's subnet was created in."
  value       = { for name, s in google_compute_subnetwork.environment : name => s.region }
}

output "enabled_apis" {
  description = "APIs enabled per environment."
  value = {
    for env_name, _ in local.environments : env_name => sort([
      for key, api in local.project_apis : api.api if api.environment == env_name
    ])
  }
}

output "production_environments" {
  description = "Environments flagged is_production — these get deletion_policy PREVENT."
  value       = sort(local.production_environments)
}

output "protected_projects" {
  description = "Projects `terraform destroy` cannot delete until their deletion_policy is changed."
  value = sort([
    for name, p in google_project.environment : p.project_id
    if p.deletion_policy == "PREVENT"
  ])
}

output "budgets" {
  description = "Monthly budget per environment that has one."
  value = {
    for name, env in local.environments : name => env.monthly_budget
    if env.monthly_budget != null
  }
}

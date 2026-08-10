terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
  }

  # Remote state is environment-specific. Configure it with a partial backend:
  #   terraform init -backend-config=environments/dev.backend.hcl
  # backend "gcs" {}
}

/**
 * No `project` on the provider: this configuration *creates* projects rather
 * than deploying into one, so every resource names its own project explicitly.
 */
provider "google" {
  region = var.region
}

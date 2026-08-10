terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
  }

  # Remote state is environment-specific. Configure it with a partial backend:
  #   terraform init -backend-config=environments/dev.backend.hcl
  # backend "s3" {}
}

/**
 * Multi-region work needs one provider instance per region. Terraform cannot
 * loop a provider block, so each region is an explicit alias — this is why the
 * template supports exactly two regions rather than an arbitrary list.
 *
 * `aws.primary` is also the default provider, so any resource that omits a
 * `provider` argument lands in the primary region.
 */

provider "aws" {
  region = var.primary_region
}

provider "aws" {
  alias  = "primary"
  region = var.primary_region
}

provider "aws" {
  alias  = "secondary"
  region = var.secondary_region
}

# Route 53 and CloudFront are global but their APIs live in us-east-1, and ACM
# certificates for CloudFront must be issued there regardless of where the
# workload runs.
provider "aws" {
  alias  = "global"
  region = "us-east-1"
}

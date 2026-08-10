# Dev / Test / Prod Projects

One **GCP project per environment**, created under a folder, each with its own
APIs, network, IAM and budget — driven from a single map.

```
folder/
├── synfra-app-dev-a1b2c3    vpc-dev   10.10.0.0/20   $100
├── synfra-app-test-a1b2c3   vpc-test  10.20.0.0/20   $200
└── synfra-app-prod-a1b2c3   vpc-prod  10.30.0.0/20   $2000  🔒 PREVENT
        │
        └─ for_each ─→ projects, APIs, VPCs, subnets, firewalls, IAM, budgets
```

## Why projects, not one project with prefixes

On GCP the **project is the real isolation boundary**. Quotas, IAM, billing, API
enablement and audit logs are all per-project, so a runaway dev workload cannot
exhaust production's quota and a dev IAM grant cannot reach production resources.

This is stronger separation than Azure resource groups or AWS tags give you, and
it is the reason this template is worth more than its Azure equivalent.

## Prerequisites — read this first

Unlike the other templates, this one operates at **organisation level** and needs
permissions most individual accounts do not have:

| Need | Role | Scope |
|---|---|---|
| Create projects | `roles/resourcemanager.projectCreator` | folder or org |
| Attach billing | `roles/billing.user` | billing account |
| Create budgets | `roles/billing.admin` | billing account |
| Set folder IAM | `roles/resourcemanager.folderAdmin` | folder |

**`roles/billing.admin` is the one that usually bites** — budget creation is a
different permission from project creation, and `budgets.tf` fails without it.

```bash
gcloud billing accounts list
gcloud resource-manager folders list --organization=ORG_ID
```

## What it creates, per environment

- **Project** (`projects.tf`) with `auto_create_network = false` — Google's
  default network spans every region with permissive firewall rules, so we build
  our own.
- **APIs** (`apis.tf`) from `common_apis` plus any `extra_apis`.
- **Custom-mode VPC and subnet** (`network.tf`) with flow logs and Private Google
  Access.
- **Three firewall rules**: internal traffic, IAP SSH/RDP
  (`35.235.240.0/20`), and an explicit deny-all-ingress at priority 65534.
- **Project IAM** — `admin_members` get `roles/editor`, `viewer_members` get
  `roles/viewer`.
- **Billing budget** (`budgets.tf`) with actual-spend alerts at 50% and 90%, plus
  a forecast alert at 100%.

## What differs between environments

Behaviour keys off `is_production`, not the environment's *name*, so a fourth
environment gets correct treatment with no new code:

| | dev / test | prod |
|---|---|---|
| `deletion_policy` | `DELETE` | `PREVENT` |
| Flow log sampling | 0.5 | 1.0 |
| `criticality` label | `low` | `high` |
| Budget | $100 / $200 | $2000 |

## Getting started

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # then set billing + folder
terraform init
terraform validate
terraform plan
terraform apply
```

Add an environment:

```hcl
environments = {
  # ...existing...
  staging = {
    subnet_cidr    = "10.40.0.0/20"
    monthly_budget = 300
    admin_members  = ["group:qa-team@example.com"]
  }
}
```

`terraform plan` shows additions only — nothing existing is touched.

## Notes

- **`for_each` over a map, not `count` over a list.** With `count`, removing
  `test` would renumber `prod` and Terraform would **delete and recreate** it.
  Recreating a GCP project is not minor: deletion is a **30-day soft delete**
  during which the project ID cannot be reused.
- **Project IDs are globally unique** across all of Google Cloud and capped at 30
  characters, hence `random_id.project_suffix` and the `substr()`.
- **`deletion_policy = "PREVENT"` on production blocks `terraform destroy`.**
  Change it and apply before any intentional teardown.
- **`disable_on_destroy = false` on APIs** is deliberate: disabling an API can
  break resources still running in the project, and Terraform cannot tell whether
  anything depends on it.
- **Subnet ranges must be distinct.** A `check` block asserts it at plan time —
  overlapping ranges cannot be peered to a hub or joined by a VPN later, and
  finding that out months in is expensive.
- **`roles/editor` is broad.** It is a reasonable starting point for a dev team in
  their own project, but production deliberately has no editors in the example —
  deploys go through a service account instead.
- **Budgets alert, they do not enforce.** Nothing stops when a threshold is
  crossed. Both actual and forecast rules are configured because the forecast one
  arrives early enough to act on.
- The provider has **no `project`** set, because this configuration creates
  projects rather than deploying into one.

## Before production

| Change | Why |
|---|---|
| **Org policies** on the folder (`constraints/compute.vmExternalIpAccess`, allowed regions) | Enforce rather than merely alert |
| Replace `roles/editor` with **narrow custom roles** | Editor can modify almost anything |
| **Separate state per environment** | A mistake in dev cannot corrupt prod's state |
| **Shared VPC** from a host project | Central network control, no peering mesh |
| **Log sink** to a central logging project | Audit trail outside the project being audited |
| Remote state (uncomment `backend "gcs"`) | Team-safe state with locking |

## Cost

The resources here are **free**: projects, VPCs, subnets, firewall rules, API
enablement and budgets carry no charge. Cost arrives with what you deploy into
them — the budgets exist so that becomes visible before the invoice does.

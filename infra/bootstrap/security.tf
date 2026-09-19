# ---------------------------------------------------------------------------
# SEC-018 organisation policies and SEC-019 Security Command Center routing.
#
# They live in bootstrap (applied once by a human) rather than in envs/*, because setting
# an org policy needs roles/orgpolicy.policyAdmin, which the CI deployer SAs must not hold.
#
# SEC-018 is applied at the PROJECT level (one policy per env project, and the boolean ones
# on the ops project too), since org-level access is not assumed. Org-level alternative
# (preferred once the organisation is administered by the team): the same constraints with
# `parent = "organizations/${var.org_id}"` (or a folder holding the three env projects), and
# drop the per-project copies; project policies then only need to exist for exceptions.
#
# SEC-019 needs Security Command Center Standard activated on the organisation (console,
# org admin: Security > Security Command Center > Standard tier) and roles/securitycenter
# .notificationConfigEditor at the org; it is therefore behind scc_notifications_enabled
# (default false). See docs/runbooks/suspected-data-breach.md.
# ---------------------------------------------------------------------------

locals {
  # Boolean constraints enforced on every project (ops + envs).
  boolean_policies = var.org_policies_enabled ? {
    for pair in setproduct(keys(local.policy_projects), [
      "sql.restrictPublicIp",   # SEC-011 / SEC-018: no public IP on Cloud SQL
      "compute.requireOsLogin", # SEC-018: OS Login on any VM (none today; guards future ones)
    ]) : "${pair[0]}:${pair[1]}" => { project = local.policy_projects[pair[0]], constraint = pair[1] }
  } : {}

  # Resource locations: env projects (data residency, SPEC 9: India). The ops project holds
  # global CI identity (WIF pool) and is left out.
  location_projects = var.org_policies_enabled ? local.env_project_ids : {}

  # Domain-restricted sharing: only principals of the customer's Cloud Identity directory.
  drs_projects = var.org_policies_enabled && length(var.allowed_policy_member_customer_ids) > 0 ? local.policy_projects : {}
}

resource "google_org_policy_policy" "boolean" {
  for_each = local.boolean_policies

  name   = "projects/${each.value.project}/policies/${each.value.constraint}"
  parent = "projects/${each.value.project}"

  spec {
    rules {
      enforce = "TRUE"
    }
  }

  depends_on = [google_project_service.ops]
}

resource "google_org_policy_policy" "resource_locations" {
  for_each = local.location_projects

  name   = "projects/${each.value}/policies/gcp.resourceLocations"
  parent = "projects/${each.value}"

  spec {
    rules {
      values {
        allowed_values = var.allowed_resource_locations
      }
    }
  }

  depends_on = [google_project_service.ops]
}

# Cloud Run api / console do not bind allUsers (invoker IAM is disabled, envs/*/main.tf), so
# this constraint does not break the load balancer path.
resource "google_org_policy_policy" "domain_restricted_sharing" {
  for_each = local.drs_projects

  name   = "projects/${each.value}/policies/iam.allowedPolicyMemberDomains"
  parent = "projects/${each.value}"

  spec {
    rules {
      values {
        allowed_values = var.allowed_policy_member_customer_ids
      }
    }
  }

  depends_on = [google_project_service.ops]
}

# --- SEC-019: SCC findings -> Pub/Sub -> security channel ----------------------------

resource "google_project_service" "scc" {
  count = var.scc_notifications_enabled ? 1 : 0

  project            = var.ops_project_id
  service            = "securitycenter.googleapis.com"
  disable_on_destroy = false
}

resource "google_pubsub_topic" "scc_findings" {
  count = var.scc_notifications_enabled ? 1 : 0

  project                    = var.ops_project_id
  name                       = "scc-findings"
  message_retention_duration = "604800s"
  labels                     = { app = "farmerapp", purpose = "sec-019" }
}

# Pull subscription the security-channel relay (Slack / e-mail bridge, human-configured:
# it needs a webhook token) consumes; also the audit trail of what was routed.
resource "google_pubsub_subscription" "scc_findings_security" {
  count = var.scc_notifications_enabled ? 1 : 0

  project                    = var.ops_project_id
  name                       = "scc-findings.security-channel"
  topic                      = google_pubsub_topic.scc_findings[0].id
  ack_deadline_seconds       = 60
  message_retention_duration = "604800s"

  expiration_policy {
    ttl = ""
  }
}

resource "google_scc_notification_config" "high" {
  count = var.scc_notifications_enabled ? 1 : 0

  config_id    = "farmerapp-high-findings"
  organization = var.org_id
  description  = "SEC-019 / OPS-013: active HIGH and CRITICAL findings in FarmerApp projects"
  pubsub_topic = google_pubsub_topic.scc_findings[0].id

  streaming_config {
    filter = "state = \"ACTIVE\" AND (severity = \"HIGH\" OR severity = \"CRITICAL\")"
  }

  depends_on = [google_project_service.scc]

  lifecycle {
    precondition {
      condition     = var.org_id != ""
      error_message = "scc_notifications_enabled needs org_id (SCC notifications are an organisation resource)."
    }
  }
}

resource "google_pubsub_topic_iam_member" "scc_publisher" {
  count = var.scc_notifications_enabled ? 1 : 0

  project = var.ops_project_id
  topic   = google_pubsub_topic.scc_findings[0].name
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${google_scc_notification_config.high[0].service_account}"
}

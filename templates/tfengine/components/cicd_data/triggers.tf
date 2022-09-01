{{- /* Copyright 2021 Google LLC

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License. */ -}}

{{- range get . "envs" -}}
# ================== Triggers for "{{.name}}" environment ==================

{{- $worker_pool := ""}}
{{- if has . "worker_pool"}}
  {{- $worker_pool = printf "projects/%s/locations/%s/workerPools/%s" .worker_pool.project .worker_pool.location .worker_pool.name}}
{{- end}}

{{- if has .triggers "test"}}

resource "google_cloudbuild_trigger" "test_{{.name}}" {
  {{- if not (get .triggers.test "run_on_push" true)}}
  disabled    = true
  {{- end}}
  project     = var.project_id
  name        = "analytics-test-{{.name}}"
  description = "Test job triggered on push event."

  included_files = [
    "**",
  ]

  {{if has $ "github" -}}
  github {
    owner = "{{$.github.owner}}"
    name  = "{{$.github.name}}"
    pull_request {
      branch = "^{{.branch_name}}$"
    }
  }
  {{- end}}

  service_account = "projects/${var.project_id}/serviceAccounts/${local.cloudbuild_sa_email}"

  filename = "cloudbuild-test.yml"

  substitutions = {
    _LOGS_BUCKET = "gs://${module.logs_bucket.bucket.name}"
  }

  depends_on = [
    google_project_service.services,
  ]
}

{{- if has .triggers.test "run_on_schedule"}}

# Create another trigger as Pull Request Cloud Build triggers cannot be used by Cloud Scheduler.
resource "google_cloudbuild_trigger" "test_scheduled_{{.name}}" {
  # Always disabled on push to branch.
  disabled    = true
  project     = var.project_id
  name        = "analytics-test-scheduled-{{.name}}"
  description = "Test job triggered on schedule."

  included_files = [
    "**",
  ]

  {{if has $ "github" -}}
  github {
    owner = "{{$.github.owner}}"
    name  = "{{$.github.name}}"
    push {
      branch = "^{{.branch_name}}$"
    }
  }
  {{- end}}

  service_account = "projects/${var.project_id}/serviceAccounts/${local.cloudbuild_sa_email}"

  filename = "cloudbuild-test.yml"

  substitutions = {
    _LOGS_BUCKET = "gs://${module.logs_bucket.bucket.name}"
  }

  depends_on = [
    google_project_service.services,
  ]
}

resource "google_cloud_scheduler_job" "test_scheduler_{{.name}}" {
  project   = var.project_id
  name      = "test-scheduler-{{.name}}"
  region    = "{{$.scheduler_region}}1" # 1 postfix hardcoded here to compensate for appengine region naming
  schedule  = "{{.triggers.test.run_on_schedule}}"
  time_zone = "Europe/London" # Keep UK to simplify the spreadsheets updates sync
  attempt_deadline = "60s"
  http_target {
    http_method = "POST"
    oauth_token {
      scope = "https://www.googleapis.com/auth/cloud-platform"
      service_account_email = "${google_service_account.cloudbuild_scheduler_sa.email}"
    }
    uri = "https://cloudbuild.googleapis.com/v1/${google_cloudbuild_trigger.test_scheduled_{{.name}}.id}:run"
    body = base64encode("{\"branchName\":\"{{.branch_name}}\"}")
  }
  depends_on = [
    google_project_service.services,
    google_app_engine_application.cloudbuild_scheduler_app,
  ]
}
{{- end}}
{{- end}}

{{- if has .triggers "run"}}

resource "google_cloudbuild_trigger" "run_{{.name}}" {
  {{- if not (get .triggers.run "run_on_push" true)}}
  disabled    = true
  {{- end}}
  project     = var.project_id
  name        = "analytics-run-{{.name}}"
  description = "Run job triggered on push event."

  included_files = [
    "**",
  ]

  {{if has $ "github" -}}
  github {
    owner = "{{$.github.owner}}"
    name  = "{{$.github.name}}"
    push {
      branch = "^{{.branch_name}}$"
    }
  }
  {{- end}}

  service_account = "projects/${var.project_id}/serviceAccounts/${local.cloudbuild_sa_email}"

  filename = "cloudbuild-run.yml"

  substitutions = {
    _LOGS_BUCKET = "gs://${module.logs_bucket.bucket.name}"
  }

  depends_on = [
    google_project_service.services,
  ]
}

{{- if has .triggers.run "run_on_schedule"}}

# Create another trigger as Pull Request Cloud Build triggers cannot be used by Cloud Scheduler.
resource "google_cloudbuild_trigger" "run_scheduled_{{.name}}" {
  # Always disabled on push to branch.
  disabled    = true
  project     = var.project_id
  name        = "analytics-run-scheduled-{{.name}}"
  description = "Run job triggered on schedule."

  included_files = [
    "**",
  ]

  {{if has $ "github" -}}
  github {
    owner = "{{$.github.owner}}"
    name  = "{{$.github.name}}"
    push {
      branch = "^{{.branch_name}}$"
    }
  }
  {{- end}}

  service_account = "projects/${var.project_id}/serviceAccounts/${local.cloudbuild_sa_email}"

  filename = "cloudbuild-run.yml"

  substitutions = {
    _LOGS_BUCKET = "gs://${module.logs_bucket.bucket.name}"
  }

  depends_on = [
    google_project_service.services,
  ]
}

resource "google_cloud_scheduler_job" "run_scheduler_{{.name}}" {
  project   = var.project_id
  name      = "run-scheduler-{{.name}}"
  region    = "{{$.scheduler_region}}1" # 1 postfix hardcoded here to compensate for appengine region naming
  schedule  = "{{.triggers.run.run_on_schedule}}"
  time_zone = "Europe/London" # Keep UK to simplify the spreadsheets updates sync
  attempt_deadline = "60s"
  http_target {
    http_method = "POST"
    oauth_token {
      scope = "https://www.googleapis.com/auth/cloud-platform"
      service_account_email = "${google_service_account.cloudbuild_scheduler_sa.email}"
    }
    uri = "https://cloudbuild.googleapis.com/v1/${google_cloudbuild_trigger.run_scheduled_{{.name}}.id}:run"
    body = base64encode("{\"branchName\":\"{{.branch_name}}\"}")
  }
  depends_on = [
    google_project_service.services,
    google_app_engine_application.cloudbuild_scheduler_app,
  ]
}
{{- end}}
{{- end}}


{{end}}

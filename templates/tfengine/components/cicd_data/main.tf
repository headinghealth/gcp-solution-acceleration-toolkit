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

# ***NOTE***: First follow
# https://cloud.google.com/cloud-build/docs/automating-builds/create-github-app-triggers#installing_the_cloud_build_app
# to install the Cloud Build app and connect your GitHub repository to your Cloud project.

{{- $hasScheduledJobs := false}}
{{- range .envs}}
  {{- if or (has .triggers "test.run_on_schedule") (has .triggers "run.run_on_schedule")}}
    {{- $hasScheduledJobs = true}}
  {{- end}}
{{- end}}

data "google_project" "analytics" {
  project_id = var.project_id
}

locals {
{{- if get .service_account "exists" false}}
  cloudbuild_sa_email = "${var.service_account}@${var.project_id}.iam.gserviceaccount.com"
  cloudbuild_sa_id = "projects/${var.project_id}/serviceAccounts/${var.service_account}@${var.project_id}.iam.gserviceaccount.com"
{{- else}}
  cloudbuild_sa_email = google_service_account.cloudbuild_sa.email
  cloudbuild_sa_id = google_service_account.cloudbuild_sa.id
{{- end}}
  services = [
    "bigquery.googleapis.com",
    "cloudbuild.googleapis.com",
    "iam.googleapis.com",
{{- if $hasScheduledJobs}}
    "appengine.googleapis.com",
    "cloudscheduler.googleapis.com",
{{- end}}
  ]
  cloudbuild_sa_viewer_roles = [
  ]
  cloudbuild_sa_editor_roles = [
  ]
  cloudbuild_sa_roles = [
    # Allow Cloud Build SA to be cloudbuild-dbt-run-sa and write logs.
    "roles/iam.serviceAccountTokenCreator",
    "roles/logging.logWriter"
  ]
}

# Cloud Build - API
resource "google_project_service" "services" {
  for_each           = toset(local.services)
  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

{{- if has . "build_viewers"}}

# IAM permissions to allow contributors to view the cloud build jobs.
resource "google_project_iam_member" "cloudbuild_builds_viewers" {
  for_each = toset([
    {{- range .build_viewers}}
    "{{.}}",
    {{- end}}
  ])
  project  = var.project_id
  role     = "roles/cloudbuild.builds.viewer"
  member   = each.value
  depends_on = [
    google_project_service.services,
  ]
}
{{- end}}

{{- if has . "build_editors"}}

# IAM permissions to allow approvers to edit/create the cloud build jobs.
resource "google_project_iam_member" "cloudbuild_builds_editors" {
  for_each = toset([
    {{- range .build_editors}}
    "{{.}}",
    {{- end}}
  ])
  project  = var.project_id
  role     = "roles/cloudbuild.builds.editor"
  member   = each.value
  depends_on = [
    google_project_service.services,
  ]
}

# IAM permission to allow approvers to impersonate the Cloud Build user-specified Service Account.
resource "google_service_account_iam_member" "cloudbuild_builds_editors" {
  for_each = toset([
    {{- range .build_editors}}
    "{{.}}",
    {{- end}}
  ])
  service_account_id = local.cloudbuild_sa_id
  role               = "roles/iam.serviceAccountUser"
  member             = each.value
  depends_on = [
    google_project_service.services,
  ]
}
{{- end}}

# IAM permissions to allow approvers and contributors to view logs.
# https://cloud.google.com/cloud-build/docs/securing-builds/store-view-build-logs
resource "google_project_iam_member" "cloudbuild_logs_viewers" {
  for_each = toset([
    {{- if has . "build_viewers"}}
    {{- range .build_viewers}}
    "{{.}}",
    {{- end}}
    {{- end}}
    {{- if has . "build_editors"}}
    {{- range .build_editors}}
    "{{.}}",
    {{- end}}
    {{- end}}
  ])
  project  = var.project_id
  role     = "roles/viewer"
  member   = each.value
  depends_on = [
    google_project_service.services,
  ]
}


# Grant Cloud Build Service Account access to the analytics project.
resource "google_project_iam_member" "cloudbuild_sa_project_iam" {
  for_each = toset(local.cloudbuild_sa_roles)
  project  = var.project_id
  role     = each.key
  member   = "serviceAccount:${local.cloudbuild_sa_email}"
  depends_on = [
    google_project_service.services,
  ]
}

# Cloud Scheduler resources.
# Cloud Scheduler requires an App Engine app created in the project.
# App Engine app cannot be destroyed once created, therefore always create it.
resource "google_app_engine_application" "cloudbuild_scheduler_app" {
  project     = var.project_id
  location_id = "{{.scheduler_region}}"
  depends_on = [
    google_project_service.services,
  ]
}

{{- if $hasScheduledJobs}}

# Service Account and its IAM permissions used for Cloud Scheduler to schedule Cloud Build triggers.
resource "google_service_account" "cloudbuild_scheduler_sa" {
  project      = var.project_id
  account_id   = "cloudbuild-scheduler-sa"
  display_name = "Cloud Build scheduler service account"
  depends_on = [
    google_project_service.services,
  ]
}

resource "google_project_iam_member" "cloudbuild_scheduler_sa_project_iam" {
  project = var.project_id
  role    = "roles/cloudbuild.builds.editor"
  member  = "serviceAccount:${google_service_account.cloudbuild_scheduler_sa.email}"
  depends_on = [
    google_project_service.services,
  ]
}

# additional role required to start cloudbuild now
resource "google_project_iam_member" "cloudbuild_scheduler_sa_project_iam_extra" {
  project = var.project_id
  role    = "roles/iam.serviceAccountUser"
  member  = "serviceAccount:${google_service_account.cloudbuild_scheduler_sa.email}"
  depends_on = [
    google_project_service.services,
  ]
}

{{- end}}

{{- if not (get .service_account "exists" false)}}
# Cloud Build - Service Account replacing the default Cloud Build Service Account.
resource "google_service_account" "cloudbuild_sa" {
  project      = var.project_id
  account_id   = var.service_account
  display_name = "Cloudbuild service account"
  description  = "Cloudbuild service account"
}
{{- end}}

# Cloud Build - Storage Bucket to store Cloud Build logs.
module "logs_bucket" {
  source  = "terraform-google-modules/cloud-storage/google//modules/simple_bucket"
  version = "~> 1.4"

  name       = var.logs_bucket
  project_id = var.project_id
  location   = "{{.storage_location}}"
}

# IAM permissions to allow Cloud Build SA to access logs bucket.
resource "google_storage_bucket_iam_member" "cloudbuild_logs_bucket_iam" {
  bucket = module.logs_bucket.bucket.name
  role   = "roles/storage.admin"
  member = "serviceAccount:${local.cloudbuild_sa_email}"
  depends_on = [
    google_project_service.services,
  ]
}

# Grant Cloud Build Service Account access to the {{.parent_type}}.
resource "google_{{.parent_type}}_iam_member" "cloudbuild_sa_{{.parent_type}}_iam" {
  for_each = toset(local.cloudbuild_sa_viewer_roles)
  {{- if eq (get . "parent_type") "organization"}}
  org_id   = {{.parent_id}}
  {{- else}}
  folder   = {{.parent_id}}
  {{- end}}
  role     = each.value
  member   = "serviceAccount:${local.cloudbuild_sa_email}"
  depends_on = [
    google_project_service.services,
  ]
}

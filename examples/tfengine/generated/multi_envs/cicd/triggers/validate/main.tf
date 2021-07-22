# Copyright 2021 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

resource "google_cloudbuild_trigger" "validate" {
  count       = var.skip ? 0 : 1
  disabled    = var.run_on_push
  provider    = google-beta
  project     = var.project_id
  name        = "tf-validate-${var.env}"
  description = "Terraform validate job triggered on push event."

  included_files = [
    "${var.terraform_root_prefix}**",
  ]

  trigger_template {
    repo_name   = var.cloud_source_repository.name
    branch_name = "^${var.branch_name}$"
  }

  filename = "${var.terraform_root_prefix}cicd/configs/tf-validate.yaml"

  substitutions = {
    _TERRAFORM_ROOT = var.terraform_root
    _MANAGED_DIRS   = var.managed_dirs
  }
}

# Create another trigger as Pull Request Cloud Build triggers cannot be used by Cloud Scheduler.
resource "google_cloudbuild_trigger" "validate_scheduled" {
  count = (!var.skip && var.run_on_schedule != "") ? 1 : 0
  # Always disabled on push to branch.
  disabled    = true
  provider    = google-beta
  project     = var.project_id
  name        = "tf-validate-scheduled-${var.env}"
  description = "Terraform validate job triggered on schedule."

  included_files = [
    "${var.terraform_root_prefix}**",
  ]

  trigger_template {
    repo_name   = var.cloud_source_repository.name
    branch_name = "^${var.branch_name}$"
  }

  filename = "${var.terraform_root_prefix}cicd/configs/tf-validate.yaml"

  substitutions = {
    _TERRAFORM_ROOT = var.terraform_root
    _MANAGED_DIRS   = var.managed_dirs
  }
}

resource "google_cloud_scheduler_job" "validate_scheduler" {
  count            = (!var.skip && var.run_on_schedule != "") ? 1 : 0
  project          = var.project_id
  name             = "validate-scheduler-${var.env}"
  region           = var.scheduler_region
  schedule         = var.run_on_schedule
  time_zone        = "America/New_York" # Eastern Standard Time (EST)
  attempt_deadline = "60s"
  http_target {
    http_method = "POST"
    oauth_token {
      scope                 = "https://www.googleapis.com/auth/cloud-platform"
      service_account_email = var.service_account_email
    }
    uri  = "https://cloudbuild.googleapis.com/v1/${google_cloudbuild_trigger.validate_scheduled.id}:run"
    body = base64encode("{\"branchName\":\"${var.branch_name}\"}")
  }
}
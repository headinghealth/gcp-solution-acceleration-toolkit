# Copyright 2021 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http:#www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

schema = {
  title                = "CICD Data Recipe"
  additionalProperties = false
  required = [
    "envs",
    "scheduler_region",
    "service_account",
    "logs_bucket"
  ]
  properties = {
    project_id = {
      description = "ID of project to deploy CICD in."
      type        = "string"
      pattern     = "^[a-z][a-z0-9\\-]{4,28}[a-z0-9]$"
    }
    github = {
      description          = "Config for GitHub Cloud Build triggers."
      type                 = "object"
      additionalProperties = false
      properties = {
        owner = {
          description = "GitHub repo owner."
          type        = "string"
        }
        name = {
          description = "GitHub repo name."
          type        = "string"
        }
      }
    }
    build_viewers = {
      description = <<EOF
        IAM members to grant `cloudbuild.builds.viewer` role in the data project
        to see CICD results.
      EOF
      type        = "array"
      items = {
        type = "string"
      }
    }
    build_editors = {
      description = <<EOF
        IAM members to grant `cloudbuild.builds.editor` role in the data project
        to see CICD results.
      EOF
      type        = "array"
      items = {
        type = "string"
      }
    }
    scheduler_region = {
      description = <<EOF
        [Region](https://cloud.google.com/appengine/docs/locations) where the scheduler
        job (or the App Engine App behind the sceneces) resides. Must be specified if
        any triggers are configured to be run on schedule.
      EOF
      type        = "string"
    }
    grant_automation_billing_user_role = {
      description = <<EOF
        Whether or not to grant automation service account the billing.user role.
        Default to true.
      EOF
      type        = "boolean"
    }
    service_account = {
      description = <<EOF
        The custom service account to run Cloud Build triggers.
        During the CICD deployment, this service account will be granted
        all necessary permissions to access your data.
        See <https://cloud.google.com/build/docs/securing-builds/configure-user-specified-service-accounts#permissions>
        for more details.
      EOF
      type        = "object"
      additionalProperties = false
      required = [
        "id",
      ]
      properties = {
        id = {
          description = "ID of the service account."
          type        = "string"
        }
        exists = {
          description = "Whether the service account exists. Defaults to 'false'."
          type        = "boolean"
        }
      }
    }
    logs_bucket = {
      description = <<EOF
        Name of the Google Cloud Storage bucket where Cloud Build logs should be written.
        The bucket will be created as part of CICD.
      EOF
      type        = "string"
    }
    storage_location = {
      description = "Location of logs bucket."
      type        = "string"
    }
    envs = {
      description = <<EOF
        Config block for per-environment resources.
      EOF
      type        = "array"
      items = {
        type                 = "object"
        additionalProperties = false
        required = [
          "name",
          "branch_name",
          "triggers",
        ]
        properties = {
          name = {
            description = <<EOF
            Name of the environment.
          EOF
            type        = "string"
          }
          branch_name = {
            description = <<EOF
            Name of the branch to set the Cloud Build Triggers to monitor.
            Regex is not supported to enforce a 1:1 mapping from a branch to a GCP
            environment.
          EOF
            type        = "string"
          }
          triggers = {
            description          = <<EOF
            Config block for the CICD Cloud Build triggers.
          EOF
            type                 = "object"
            additionalProperties = false
            properties = {
              test = {
                description          = <<EOF
                Config block for the presubmit validation Cloud Build trigger. If specified, create
                the trigger and grant the Cloud Build Service Account necessary permissions to
                perform the build.
              EOF
                type                 = "object"
                additionalProperties = false
                properties = {
                  run_on_push = {
                    description = <<EOF
                    Whether or not to be automatically triggered from a PR/push to branch.
                    Default to true.
                  EOF
                    type        = "boolean"
                  }
                  run_on_schedule = {
                    description = <<EOF
                    Whether or not to be automatically triggered according a specified schedule.
                    The schedule is specified using [unix-cron format](https://cloud.google.com/scheduler/docs/configuring/cron-job-schedules#defining_the_job_schedule)
                    at Eastern Standard Time (EST). Default to none.
                  EOF
                    type        = "string"
                  }
                }
              }
              run = {
                description          = <<EOF
                Config block for the run Cloud Build trigger.
                If specified, create the trigger and grant the Cloud Build Service Account
                necessary permissions to perform the build.
              EOF
                type                 = "object"
                additionalProperties = false
                properties = {
                  run_on_push = {
                    description = <<EOF
                    Whether or not to be automatically triggered from a PR/push to branch.
                    Default to true.
                  EOF
                    type        = "boolean"
                  }
                  run_on_schedule = {
                    description = <<EOF
                    Whether or not to be automatically triggered according a specified schedule.
                    The schedule is specified using [unix-cron format](https://cloud.google.com/scheduler/docs/configuring/cron-job-schedules#defining_the_job_schedule)
                    at Eastern Standard Time (EST). Default to none.
                  EOF
                    type        = "string"
                  }
                  run_on_schedule_hourly = {
                    description = <<EOF
                    Whether or not to be automatically triggered according a specified schedule.
                    The schedule is specified using [unix-cron format](https://cloud.google.com/scheduler/docs/configuring/cron-job-schedules#defining_the_job_schedule)
                    at Eastern Standard Time (EST). Default to none.
                  EOF
                    type        = "string"
                  }
                }
              }
            }
          }
          worker_pool = {
            description          = <<EOF
              Optional Cloud Build private worker pool configuration.
              Required for CICD to access resources in a private network, e.g. GKE clusters with a private endpoint.
            EOF
            type                 = "object"
            additionalProperties = false
            required = [
              "project",
              "location",
              "name"
            ]
            properties = {
              project = {
                description = "The project worker pool belongs."
                type        = "string"
              }
              location = {
                description = "GCP region of the worker pool. Example: us-central1."
                type        = "string"
              }
              name = {
                description = "Name of the worker pool."
                type        = "string"
              }
            }
          }
        }
      }
    }
    terraform_addons = {
      description = <<EOF
        Additional Terraform configuration for the cicd deployment.
        For schema see ./deployment.hcl.
      EOF
    }
  }
}

template "deployment" {
  recipe_path = "./deployment.hcl"
  passthrough = [
    "terraform_addons",
  ]
}

template "cicd_data" {
  component_path = "../components/cicd_data"
}

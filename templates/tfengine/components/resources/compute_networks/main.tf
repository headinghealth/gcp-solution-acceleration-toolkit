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

{{range get . "compute_networks"}}
{{$resource_name := resourceName . "name" -}}
{{$has_secondary_ranges := false -}}

module "{{$resource_name}}" {
  source  = "terraform-google-modules/network/google"
  version = "~> 4.0.1"

  network_name = "{{.name}}"
  project_id   = module.project.project_id

  subnets = [
    {{- range .subnets}}
    {
      subnet_name           = "{{.name}}"
      subnet_ip             = "{{.ip_range}}"
      subnet_region         = "{{get . "compute_region" $.compute_region}}"
      subnet_flow_logs      = true
      subnet_private_access = true
    },

    {{- if has . "secondary_ranges"}}
    {{- $has_secondary_ranges = true}}
    {{- end}}
    {{- end}}
  ]

  {{- if $has_secondary_ranges}}
  secondary_ranges = {
    {{- range .subnets}}
    {{- if has . "secondary_ranges"}}
    "{{.name}}" = [
      {{- range .secondary_ranges}}
      {
        range_name    = "{{.name}}"
        ip_cidr_range = "{{.ip_range}}"
      },
      {{- end}}
    ],
    {{- end}}
    {{- end}}
  }
  {{- end}}

  {{- if has . "firewall_rules"}}
  firewall_rules = [
    {{- range .firewall_rules}}
    {
      name                    = "{{.name}}"
      description             = "{{.description}}"
      direction               = "{{.direction}}"
      {{- if has . "priority"}}
      priority                = "{{.priority}}"
      {{- end}}
      ranges                  = {{hcl .ranges}}
      {{- if has . "source_tags"}}
      source_tags             = {{hcl .source_tags}}
      {{- end}}
      {{- if has . "source_service_accounts"}}
      source_service_accounts = {{hcl .source_service_accounts}}
      {{- end}}
      {{- if has . "target_tags"}}
      target_tags             = {{hcl .target_tags}}
      {{- end}}
      {{- if has . "target_service_accounts"}}
      target_service_accounts = "{{.target_service_accounts}}"
      {{- end}}

      {{- if has . "allow"}}
      allow = [
        {{- range .allow}}
        {
          protocol = "{{.protocol}}"
          ports    = {{hcl .ports}}
        },
        {{- end}}
      ]
      {{- end}}

      {{- if has . "deny"}}
      deny = [
        {{- range .deny}}
        {
          protocol = "{{.protocol}}"
          ports    = {{hcl .ports}}
        },
        {{- end}}
      ]
      {{- end}}

      {{- if has . "log_config_metadata"}}
      log_config = {
        metadata = "{{.log_config_metadata}}"
      }
      {{- end}}
    },
    {{- end}}
  ]
  {{- end}}
}

{{- if has . "serverless_connectors"}}
{{- range .serverless_connectors}}
module "{{$resource_name}}_{{.name}}" {
  source     = "terraform-google-modules/network/google//modules/vpc-serverless-connector-beta"
  project_id = module.project.project_id
  vpc_connectors = [{
      name        = "{{.name}}"
      region      = "{{get . "compute_region" $.compute_region}}"
      subnet_name = module.{{$resource_name}}.subnets["{{get . "compute_region" $.compute_region}}/{{.subnet_name}}"].name
      host_project_id = module.project.project_id
      machine_type  = "{{.machine_type}}"
      min_instances = "{{.min_instances}}"
      max_instances = "{{.max_instances}}"
    }
  ]
  depends_on = [
    module.project
  ]
}
{{- end}}
{{- end}}

{{- if has . "cloud_sql_private_service_access"}}
module "cloud_sql_private_service_access_{{$resource_name}}" {
  source  = "GoogleCloudPlatform/sql-db/google//modules/private_service_access"
  version = "~> 4.5.0"

  project_id  = module.project.project_id
  vpc_network = module.{{$resource_name}}.network_name
  depends_on = [
    module.project
  ]
}
{{- end}}
{{- end}}

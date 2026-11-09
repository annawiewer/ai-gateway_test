# Optional gateway-wide client IP allow list on the default workspace, covering models and
# MCP tool servers. Follows the Azure/aigateway gateway baselines lab: read the workspace
# policies, keep every entry except an earlier ipFilter, then PATCH the merged list.
locals {
  gateway_policy_type       = "${local.gateway_type}/workspaces@${local.gateway_policy_api_version}"
  gateway_ip_filter_targets = local.gateway_is_2026 && var.gateway_allowed_client_cidrs != null ? toset(["default"]) : toset([])
}

data "azapi_resource" "gateway_policies" {
  for_each = local.gateway_ip_filter_targets
  type     = local.gateway_policy_type
  # Use the local, not a direct gateway reference, which would defer this read on every
  # gateway change. A new gateway still has an unknown id, so its read waits for apply.
  resource_id            = local.gateway_workspace_id
  response_export_values = ["properties.policies"]
}

resource "azapi_resource_action" "gateway_ip_filter" {
  for_each    = local.gateway_ip_filter_targets
  type        = local.gateway_policy_type
  resource_id = local.gateway_workspace_id
  method      = "PATCH"
  # Runs on create and on body changes. Destroying it sends no request, so apply an
  # empty list to remove the filter before setting the variable back to null.
  when = "apply"
  body = {
    properties = {
      policies = concat(try([
        for policy in data.azapi_resource.gateway_policies[each.key].output.properties.policies :
        policy if lower(try(policy.type, "")) != "ipfilter"
        ], []), length(var.gateway_allowed_client_cidrs) == 0 ? [] : [{
        type       = "ipFilter"
        action     = "Allow"
        cidrRanges = sort(distinct(var.gateway_allowed_client_cidrs))
      }])
    }
  }
  # PATCH the workspace after its child resources to avoid concurrent workspace writes.
  depends_on = [
    azapi_resource.catalog_model,
    azapi_resource.model_alias,
    azapi_resource.mcp_tool_server,
    azapi_resource.telemetry_exporter,
  ]
}

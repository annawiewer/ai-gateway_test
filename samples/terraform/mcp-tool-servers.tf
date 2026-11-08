# Registers existing remote MCP servers as tool servers on the 2026 gateway.
# Re-implemented from damienaicheh/blue-octopus (catalog/ai-gateway/standalone/ai_gateway_mcp.tf at 3222da9).
resource "azapi_resource" "mcp_tool_server" {
  for_each = local.gateway_is_2026 ? var.mcp_tool_servers : {}
  # This preview type is not yet present in AzAPI's bundled schema.
  schema_validation_enabled = false
  type                      = "${local.gateway_type}/workspaces/toolServers@${local.gateway_tool_server_api_version}"
  name                      = each.key
  parent_id                 = local.gateway_workspace_id
  body = {
    properties = {
      displayName = each.value.display_name
      description = coalesce(each.value.description, each.value.display_name)
      type        = "mcp"
      policies = [{
        type           = "requestRateLimit"
        callsPerPeriod = each.value.calls_per_period
        periodSeconds  = each.value.period_seconds
        counterKey     = ["identity"]
      }]
      endpoints = [{
        namespace = each.key
        kind      = "mcp"
        mcp = {
          url       = each.value.url
          transport = "streamableHttp"
        }
      }]
    }
  }
  create_headers = { "If-None-Match" = "*" }
  delete_headers = { "If-Match" = "*" }
  # As with aliases, updates need PATCH or an If-Match PUT; AzAPI updates send a plain PUT.
  # Replace changed tool servers explicitly instead of relying on an unconditional update.
  replace_triggers_refs = ["properties"]
}

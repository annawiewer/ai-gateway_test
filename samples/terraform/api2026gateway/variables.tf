variable "subscription_id" {
  description = "Explicitly approved subscription for a future isolated test. No subscription is inferred from Azure CLI."
  type        = string
}

variable "environment_name" {
  description = "New environment label. Names additionally include the standalone contract identifier to distinguish them from legacy resources."
  type        = string
  default     = "api2026gateway"
}

variable "location" {
  description = "Explicit Foundry/Storage/Registry/monitoring region. Verify availability and model quota before any live deployment."
  type        = string
}

variable "gateway_location" {
  description = "Explicit region enabled for the standalone 2026 gateway. An optional backend subnet must be in this region."
  type        = string
}

variable "api2026_resource_group_name" {
  description = "Optional exact single RG name for fresh state only. Null preserves three separate groups; not a migration switch."
  type        = string
  default     = null
}

variable "api2026_private_lab_enabled" {
  description = "Opt into the owned single-RG private backend foundation and verification client, not gateway private ingress or a hosted agent."
  type        = bool
  default     = false
  nullable    = false
}

variable "api2026_private_lab_ssh_public_key" {
  description = "Fresh OpenSSH public key required only for the private lab. Never provide private key material."
  type        = string
  default     = null
}

variable "gateway_backend_subnet_id" {
  description = "Optional existing creation-time outbound subnet; requires Microsoft.App/environments delegation. Not a private-ingress or DNS configuration."
  type        = string
  default     = ""
  nullable    = false
}

variable "standalone_backend_public_network_access" {
  description = "Optional Enabled/Disabled backend PaaS and monitoring access. Null preserves the baseline. The owned private lab requires Disabled; otherwise Disabled needs separately provisioned private connectivity and an external gateway_backend_subnet_id."
  type        = string
  default     = null
}

variable "gateway_access_principals" {
  description = "Optional additive Entra caller access at gateway scope; does not revoke or replace the default API key."
  type = map(object({
    principal_id   = string
    principal_type = optional(string, "ServicePrincipal")
  }))
  default  = {}
  nullable = false
}

variable "developer_principal_id" {
  description = "Optional explicit Entra object ID for developer roles. Empty creates no developer grants."
  type        = string
  default     = ""
}

variable "developer_principal_type" {
  description = "User, Group or ServicePrincipal for optional developer grants."
  type        = string
  default     = "User"
}

variable "model_deployments" {
  description = "Optional complete replacement of the default model deployments and limits. Foundry content filtering stays bound to Microsoft.DefaultV2. If deployment keys change, also supply matching model_aliases."
  type = map(object({
    model_name    = string
    model_version = string
    model_format  = optional(string, "OpenAI")
    sku_name      = optional(string, "GlobalStandard")
    capacity      = number
    token_limit   = number
    api_format    = optional(string, "OpenAIChatCompletions")
    endpoints     = optional(list(string), ["/openai/v1/chat/completions", "/openai/v1/responses"])
    description   = optional(string, "Foundry model routed through AI Gateway.")
    cost_limit    = optional(number)
    request_limit = optional(number)
    # Keep this field typed so old profiles fail explicitly instead of dropping it.
    content_safety_severity = optional(string)
  }))
  default = null
  validation {
    condition = var.model_deployments == null ? true : alltrue([
      for model in var.model_deployments : model.content_safety_severity == null
    ])
    error_message = "Gateway content_safety_severity is unsupported. Omit it; Microsoft.DefaultV2 supplies the backend content filter."
  }
}

variable "model_allowed_client_cidrs" {
  description = "Optional model-call allow list of approved caller egress IPv4/IPv6 CIDRs. Empty adds no IP policy; does not configure private ingress, management access or MCP filtering."
  type        = list(string)
  default     = []
  nullable    = false
}

variable "model_aliases" {
  description = "Optional complete replacement of the default aliases. Backends reference keys in model_deployments."
  type = map(object({
    alias_name  = string
    description = optional(string, "Foundry models routed through AI Gateway.")
    backend_models = list(object({
      deployment = string
      priority   = optional(number, 0)
      weight     = optional(number, 100)
    }))
  }))
  default = null
}

variable "tags" {
  description = "Additional resource tags."
  type        = map(string)
  default     = {}
}

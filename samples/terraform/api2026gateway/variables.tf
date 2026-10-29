variable "subscription_id" {
  description = "Explicitly approved subscription for a future isolated test. No subscription is inferred from Azure CLI."
  type        = string
}

variable "environment_name" {
  description = "New environment label. Names additionally include the 2026 contract to distinguish them from legacy resources."
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

variable "gateway_backend_subnet_id" {
  description = "Optional existing creation-time outbound subnet; requires Microsoft.App/environments delegation. Not a private-ingress or DNS configuration."
  type        = string
  default     = ""
  nullable    = false
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
  description = "Optional complete replacement of the Bicep model profile. If deployment keys change, also supply matching model_aliases."
  type = map(object({
    model_name              = string
    model_version           = string
    model_format            = optional(string, "OpenAI")
    sku_name                = optional(string, "GlobalStandard")
    capacity                = number
    token_limit             = number
    api_format              = optional(string, "OpenAIChatCompletions")
    endpoints               = optional(list(string), ["/openai/v1/chat/completions", "/openai/v1/responses"])
    description             = optional(string, "Foundry model routed through AI Gateway.")
    cost_limit              = optional(number)
    content_safety_severity = optional(string)
  }))
  default = null
}

variable "model_aliases" {
  description = "Optional complete replacement of the two Bicep aliases. Backends reference keys in model_deployments."
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

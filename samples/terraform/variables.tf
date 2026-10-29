variable "subscription_id" {
  description = "Azure subscription containing the application resource groups."
  type        = string
  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.subscription_id))
    error_message = "subscription_id must be a UUID."
  }
}

variable "gateway_contract" {
  description = "legacy preserves service/AIGateway and its existing networking. 2026 selects the isolated, experimental Bicep-aligned aigateways contract; never switch an existing state."
  type        = string
  default     = "legacy"
  nullable    = false
  validation {
    condition     = contains(["legacy", "2026"], var.gateway_contract)
    error_message = "gateway_contract must be legacy or 2026. Use the api2026gateway entry point and separate state for the new contract."
  }
}

variable "gateway_backend_subnet_id" {
  description = "Optional existing outbound backend subnet for a NEW 2026 gateway. Requires Microsoft.App/environments delegation and the gateway region. Creation-only; does not configure private ingress, DNS, NSGs or routes."
  type        = string
  default     = ""
  nullable    = false
  validation {
    condition = var.gateway_backend_subnet_id == "" || (
      var.gateway_contract == "2026" && can(regex(local.private_subnet_id_pattern, var.gateway_backend_subnet_id))
    )
    error_message = "gateway_backend_subnet_id must be empty or a full existing subnet ARM ID with gateway_contract = 2026."
  }
}

variable "gateway_access_principals" {
  description = "Optional caller identities granted AI Gateway Models User at gateway scope. Additive Entra access for all gateway models; API keys and existing agent/test-VM authentication remain unchanged."
  type = map(object({
    principal_id   = string
    principal_type = optional(string, "ServicePrincipal")
  }))
  default  = {}
  nullable = false
  validation {
    condition = alltrue([for principal in var.gateway_access_principals : try(
      can(regex("(?i)^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", principal.principal_id)) &&
      contains(["User", "Group", "ServicePrincipal"], principal.principal_type), false
    )])
    error_message = "Each gateway caller requires an Entra object UUID and principal_type User, Group or ServicePrincipal."
  }
  validation {
    condition = try(
      length(distinct([for principal in var.gateway_access_principals : lower(principal.principal_id)])) == length(var.gateway_access_principals),
      false
    )
    error_message = "Each gateway caller object ID must appear only once, regardless of letter case."
  }
}

variable "environment_name" {
  description = "Short environment label used in the shared resource group name and tags."
  type        = string
  default     = "aigateway"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,31}$", var.environment_name))
    error_message = "Use 1-32 lowercase letters, numbers, or hyphens, starting with a letter."
  }
}

variable "backend_revision" {
  description = "Optional stable revision for deliberate backend recreation with fresh names. Does not rename the gateway or shared group. Changing it replaces backend resources."
  type        = string
  default     = ""
  validation {
    condition     = var.backend_revision == "" || can(regex("^[a-z0-9][a-z0-9-]{0,31}$", var.backend_revision))
    error_message = "backend_revision must be empty or 1-32 lowercase letters, digits or hyphens, starting with a letter or digit."
  }
}

variable "retain_legacy_resource_groups" {
  description = "Migration-only safety switch: retain the old empty Models/Agents groups during backend rebuild. Set false after acceptance and inventory review; new resources always use the gateway group."
  type        = bool
  default     = false
}

variable "location" {
  description = "Region supporting Foundry hosted agents, the selected models, storage, ACR, and monitoring. Confirm availability before applying."
  type        = string
  validation {
    condition     = length(trimspace(var.location)) > 0
    error_message = "location must not be empty."
  }
}

variable "gateway_location" {
  description = "Region in which the subscription is enabled for the preview AIGateway SKU."
  type        = string
  validation {
    condition     = length(trimspace(var.gateway_location)) > 0
    error_message = "gateway_location must not be empty."
  }
}

variable "storage_public_network_access" {
  description = "Storage public network access. Use Disabled when required by Azure Policy. The optional Blob private endpoint connects VNet clients, not hosted-agent runtimes."
  type        = string
  default     = "Enabled"
  validation {
    condition     = contains(["Enabled", "Disabled"], var.storage_public_network_access)
    error_message = "storage_public_network_access must be Enabled or Disabled."
  }
}

variable "enable_private_networking" {
  description = "Enable gateway/model private endpoints and gateway outbound VNet integration using the selected network ownership mode. Does not by itself enable private hosted-agent execution."
  type        = bool
  default     = false
  validation {
    condition     = !var.enable_private_networking || var.gateway_contract == "legacy"
    error_message = "The legacy private endpoint/DNS/public-disable contract is not verified for 2026. Do not reuse private profiles; gateway_backend_subnet_id only prepares outbound integration."
  }
}

variable "private_network_mode" {
  description = "create manages the sample network/DNS foundation; existing consumes platform-owned subnets and DNS zones. Changing an already deployed mode requires a reviewed migration."
  type        = string
  default     = "create"
  nullable    = false
  validation {
    condition     = contains(["create", "existing"], var.private_network_mode)
    error_message = "private_network_mode must be create or existing."
  }
  validation {
    condition     = var.private_network_mode != "existing" || var.enable_private_networking
    error_message = "Existing network mode requires enable_private_networking; it is not a public-access fallback."
  }
}

variable "existing_private_network" {
  description = "Platform-owned subnet and central DNS zone IDs. Endpoint subnet keys are gateway/models and enabled storage/agents/registry extras. This input does not transfer resource ownership."
  type = object({
    gateway_subnet_id    = string
    endpoint_subnet_ids  = map(string)
    private_dns_zone_ids = map(string)
    agent_subnet_id      = optional(string)
    client_subnet_id     = optional(string)
  })
  default = null
  validation {
    condition     = (var.private_network_mode == "existing") == (var.existing_private_network != null)
    error_message = "Supply existing_private_network only in existing mode; existing mode never creates missing network infrastructure."
  }
  validation {
    condition = var.existing_private_network == null || try(alltrue([
      for id in concat(
        [var.existing_private_network.gateway_subnet_id],
        values(var.existing_private_network.endpoint_subnet_ids),
        compact([var.existing_private_network.agent_subnet_id, var.existing_private_network.client_subnet_id])
      ) : can(regex(local.private_subnet_id_pattern, id))
    ]), false)
    error_message = "Existing network inputs must be full Azure subnet resource IDs, including subscription, resource group, VNet and subnet."
  }
  validation {
    condition = var.existing_private_network == null || try(alltrue([
      for key in local.private_endpoint_keys : contains(keys(var.existing_private_network.endpoint_subnet_ids), key)
    ]), false)
    error_message = "Supply an endpoint_subnet_ids entry for gateway/models and every enabled storage/agents/registry private endpoint."
  }
  validation {
    condition = var.existing_private_network == null || try(alltrue([
      for key in local.private_endpoint_keys :
      lower(split("/", var.existing_private_network.endpoint_subnet_ids[key])[2]) == lower(var.subscription_id)
    ]), false)
    error_message = "Endpoint subnets must belong to subscription_id: Azure requires private endpoints and their VNets in the same subscription, and this sample keeps endpoints in the workload resource group. Central DNS zones may be in another subscription."
  }
  validation {
    condition = var.existing_private_network == null || try(
      (!var.enable_private_hosted_agent || can(regex(local.private_subnet_id_pattern, var.existing_private_network.agent_subnet_id))) &&
      (!var.enable_private_test_client || can(regex(local.private_subnet_id_pattern, var.existing_private_network.client_subnet_id))),
      false
    )
    error_message = "Existing mode requires agent_subnet_id for private hosted agents and client_subnet_id for the optional test VM."
  }
  validation {
    condition = var.existing_private_network == null || !var.enable_private_test_client || try(
      lower(split("/", var.existing_private_network.client_subnet_id)[2]) == lower(var.subscription_id),
      false
    )
    error_message = "The optional test-client subnet must belong to subscription_id, because its VM and NIC remain in the workload resource group."
  }
  validation {
    condition = var.existing_private_network == null || try(
      alltrue([for id in values(var.existing_private_network.endpoint_subnet_ids) :
        lower(id) != lower(var.existing_private_network.gateway_subnet_id)
      ]) &&
      (var.enable_private_hosted_agent ? (
        lower(var.existing_private_network.agent_subnet_id) != lower(var.existing_private_network.gateway_subnet_id) &&
        alltrue([for id in values(var.existing_private_network.endpoint_subnet_ids) :
          lower(id) != lower(var.existing_private_network.agent_subnet_id)
        ])
      ) : true),
      false
    )
    error_message = "Gateway and agent integration require distinct delegated subnets, separate from all private endpoint subnets."
  }
  validation {
    condition = var.existing_private_network == null || try(
      alltrue([for id in values(var.existing_private_network.private_dns_zone_ids) :
        can(regex(local.private_dns_zone_id_pattern, id))
      ]) &&
      alltrue([for key, name in local.private_dns_zones :
        endswith(lower(var.existing_private_network.private_dns_zone_ids[key]), "/${name}")
      ]),
      false
    )
    error_message = "Supply full central DNS zone IDs for gateway/cognitiveservices/openai/services and enabled storage/registry zones, with their expected privatelink names."
  }
}

variable "private_dns_zone_group_management" {
  description = "workload creates private endpoint DNS zone groups; platform leaves them to platform policy/automation. Platform-managed DNS must be ready before private calls or agent use."
  type        = string
  default     = "workload"
  nullable    = false
  validation {
    condition     = contains(["workload", "platform"], var.private_dns_zone_group_management)
    error_message = "private_dns_zone_group_management must be workload or platform."
  }
  validation {
    condition     = var.private_dns_zone_group_management != "platform" || (var.enable_private_networking && var.private_network_mode == "existing")
    error_message = "Platform-managed DNS zone groups require existing private networking."
  }
}

variable "enable_private_hosted_agent" {
  description = "Add a separate private Foundry account/project with Basic VNet injection into the selected delegated subnet and private registry access. Keeps the original agent account and outputs unchanged; does not deploy an agent."
  type        = bool
  default     = false
  validation {
    condition = !var.enable_private_hosted_agent || (
      var.enable_private_networking &&
      (var.private_network_mode == "existing" || lower(var.location) == lower(var.gateway_location))
    )
    error_message = "Private hosted agents require private networking. The created shared VNet requires location to equal gateway_location; existing agent subnet region is checked separately."
  }
  validation {
    condition = !var.enable_private_hosted_agent || var.private_network_mode == "existing" || can(regex(
      "^(10\\.|172\\.(1[6-9]|2[0-9]|3[01])\\.|192\\.168\\.)", var.private_network_address_prefix
    ))
    error_message = "The private hosted-agent VNet must use RFC1918 IPv4 address space."
  }
}

variable "private_hosted_agent_runtime_principal_id" {
  description = "Optional actual managed-identity object ID discovered after private agent deployment. Grants gateway key retrieval at gateway scope only; never supply the old agent identity as a placeholder."
  type        = string
  default     = ""
  validation {
    condition = var.private_hosted_agent_runtime_principal_id == "" || (
      var.enable_private_hosted_agent &&
      can(regex("(?i)^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.private_hosted_agent_runtime_principal_id))
    )
    error_message = "Supply an actual Entra object UUID only when enable_private_hosted_agent is true, or leave the runtime principal empty."
  }
}

variable "enable_storage_private_endpoint" {
  description = "Add a Blob private endpoint in the selected network. Requires private networking and disabled storage public access. The optional test VM receives account-scoped Blob Data Reader for a read-only connectivity probe."
  type        = bool
  default     = false
  validation {
    condition     = !var.enable_storage_private_endpoint || (var.enable_private_networking && var.storage_public_network_access == "Disabled")
    error_message = "The storage private endpoint requires enable_private_networking and storage_public_network_access = Disabled."
  }
}

variable "private_network_address_prefix" {
  description = "Non-overlapping IPv4 /16 for the optional PoC VNet; three /24 subnets, plus subnet index 3 for optional private hosted agents, are derived from it."
  type        = string
  default     = "10.247.0.0/16"
  validation {
    condition     = var.private_network_mode == "existing" ? true : try(can(cidrnetmask(var.private_network_address_prefix)) && endswith(var.private_network_address_prefix, "/16"), false)
    error_message = "In create mode, private_network_address_prefix must be a valid IPv4 /16."
  }
}

variable "gateway_public_network_access" {
  description = "Gateway public ingress. For an existing gateway, select Disabled after private endpoint approval and private-route verification; preserve that end state on subsequent plans. First-create and Terraform update behavior require live validation."
  type        = string
  default     = "Enabled"
  validation {
    condition = (
      contains(["Enabled", "Disabled"], var.gateway_public_network_access) &&
      (var.gateway_public_network_access != "Disabled" || var.enable_private_networking)
    )
    error_message = "Use Enabled or Disabled; disabling requires enable_private_networking."
  }
}

variable "models_public_network_access" {
  description = "Keep Enabled until gateway outbound private connectivity is ready, then set Disabled and retest."
  type        = string
  default     = "Enabled"
  validation {
    condition = (
      contains(["Enabled", "Disabled"], var.models_public_network_access) &&
      (var.models_public_network_access != "Disabled" || var.enable_private_networking)
    )
    error_message = "Use Enabled or Disabled; disabling requires enable_private_networking."
  }
}

variable "gateway_private_endpoint_manual_approval" {
  description = "Use a separately named manual-request gateway endpoint and approve it after creation. Changing this replaces only the gateway private endpoint; review migration first."
  type        = bool
  default     = false
  validation {
    condition     = !var.gateway_private_endpoint_manual_approval || var.enable_private_networking
    error_message = "Manual gateway endpoint approval requires enable_private_networking."
  }
}

variable "enable_private_test_client" {
  description = "Create a billable private Ubuntu test VM with no public IP and narrowly scoped API-key retrieval access. Existing mode uses the supplied client subnet and platform-owned NSG/egress policy."
  type        = bool
  default     = false
  validation {
    condition     = !var.enable_private_test_client || var.enable_private_networking
    error_message = "The private test client requires enable_private_networking."
  }
}

variable "private_test_client_ssh_public_key" {
  description = "OpenSSH public key required only when the test VM is enabled. No private key or password belongs in Terraform."
  type        = string
  default     = ""
  validation {
    condition = (
      !var.enable_private_test_client ||
      can(regex("^ssh-(ed25519|rsa) [A-Za-z0-9+/=]+( .*)?$", trimspace(var.private_test_client_ssh_public_key)))
    )
    error_message = "Supply an OpenSSH ed25519 or RSA public key when enabling the private test client."
  }
}

variable "private_test_client_vm_size" {
  description = "Small test VM SKU; verify regional quota and availability before enabling."
  type        = string
  default     = "Standard_B2s_v2"
}

variable "publisher_email" {
  description = "Publisher contact email required only for the legacy API Management gateway; not sent to aigateways."
  type        = string
  default     = ""
  validation {
    condition     = var.gateway_contract == "2026" || can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.publisher_email))
    error_message = "publisher_email must be an email address for the legacy gateway."
  }
}

variable "publisher_name" {
  description = "Publisher display name for the gateway."
  type        = string
  default     = "AI Gateway"
}

variable "model_deployments" {
  description = "Foundry deployments keyed by ARM-safe deployment name. Select model versions, deployment SKUs, and quota available to your subscription."
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
  validation {
    condition = length(var.model_deployments) > 0 && alltrue([
      for name, model in var.model_deployments :
      can(regex("^[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}$", name)) &&
      length(trimspace(model.model_name)) > 0 &&
      length(trimspace(model.model_version)) > 0 &&
      model.capacity >= 1 && floor(model.capacity) == model.capacity &&
      model.token_limit >= 1 && floor(model.token_limit) == model.token_limit &&
      length(model.endpoints) > 0
    ])
    error_message = "Provide at least one model with an ARM-safe name, explicit model name/version, positive integer capacity/token_limit, and at least one endpoint."
  }
  validation {
    condition = alltrue([for model in var.model_deployments :
      model.cost_limit == null ? true : model.cost_limit > 0
    ])
    error_message = "An optional monthly cost_limit must be positive. This preview policy is not an Azure billing budget."
  }
  validation {
    condition = alltrue([for model in var.model_deployments :
      model.content_safety_severity == null ? true : contains(["Low", "Medium", "High"], model.content_safety_severity)
    ])
    error_message = "An optional content_safety_severity must be Low, Medium or High."
  }
}

variable "model_aliases" {
  description = "Optional aliases keyed by ARM name. Null preserves one alias per deployment. Explicit routes use unique deployment keys, priority 0-100 and relative weight 1-100."
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
  validation {
    condition = var.model_aliases == null ? true : (
      length(var.model_aliases) > 0 &&
      length(distinct([for alias in var.model_aliases : alias.alias_name])) == length(var.model_aliases) &&
      alltrue([for name, alias in var.model_aliases : try(
        can(regex("^[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}$", name)) &&
        length(trimspace(alias.alias_name)) > 0 &&
        length(alias.backend_models) >= 1 && length(alias.backend_models) <= 30 &&
        length(distinct([for backend in alias.backend_models : backend.deployment])) == length(alias.backend_models) &&
        alltrue([for backend in alias.backend_models :
          contains(keys(var.model_deployments), backend.deployment) &&
          backend.priority >= 0 && backend.priority <= 100 && floor(backend.priority) == backend.priority &&
          backend.weight >= 1 && backend.weight <= 100 && floor(backend.weight) == backend.weight
        ]), false
      )])
    )
    error_message = "Aliases require unique callable names, ARM-safe keys, 1-30 distinct existing deployments, integer priority 0-100 and integer weight 1-100."
  }
  validation {
    condition = var.model_aliases == null ? true : alltrue([for alias in var.model_aliases : try(
      length(distinct([for backend in alias.backend_models : var.model_deployments[backend.deployment].api_format])) == 1 &&
      length(setintersection([for backend in alias.backend_models : toset(var.model_deployments[backend.deployment].endpoints)]...)) > 0,
      false
    )])
    error_message = "Every alias must route to models with the same API format and at least one common supported endpoint."
  }
}

variable "developer_principal_id" {
  description = "Optional Entra object ID for development access. Empty disables all developer role assignments."
  type        = string
  default     = ""
  validation {
    condition     = var.developer_principal_id == "" || can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.developer_principal_id))
    error_message = "developer_principal_id must be empty or a UUID."
  }
}

variable "developer_principal_type" {
  description = "Entra principal type for optional development access."
  type        = string
  default     = "User"
  validation {
    condition     = contains(["User", "Group", "ServicePrincipal"], var.developer_principal_type)
    error_message = "Use User, Group, or ServicePrincipal."
  }
}

variable "project_display_name" {
  description = "Display name for the Foundry hosted-agent project."
  type        = string
  default     = "AI Gateway hosted agents"
}

variable "project_description" {
  description = "Description of the hosted-agent project."
  type        = string
  default     = "Hosted-agent infrastructure with a separate Foundry model account and AI Gateway."
}

variable "tags" {
  description = "Additional tags for supported Azure resources."
  type        = map(string)
  default     = {}
}

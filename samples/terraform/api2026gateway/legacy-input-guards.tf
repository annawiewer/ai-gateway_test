# Terraform only warns about undeclared .tfvars inputs. Recognize these names
# solely to reject old private profiles instead of silently deploying publicly.
locals {
  supplied_legacy_network_inputs = [for name, value in {
    private_network_mode                      = var.private_network_mode
    existing_private_network                  = var.existing_private_network
    private_dns_zone_group_management         = var.private_dns_zone_group_management
    enable_private_hosted_agent               = var.enable_private_hosted_agent
    private_hosted_agent_runtime_principal_id = var.private_hosted_agent_runtime_principal_id
    enable_private_test_client                = var.enable_private_test_client
    enable_storage_private_endpoint           = var.enable_storage_private_endpoint
    storage_public_network_access             = var.storage_public_network_access
    gateway_public_network_access             = var.gateway_public_network_access
    models_public_network_access              = var.models_public_network_access
    gateway_private_endpoint_manual_approval  = var.gateway_private_endpoint_manual_approval
    private_network_address_prefix            = var.private_network_address_prefix
    private_test_client_ssh_public_key        = var.private_test_client_ssh_public_key
    private_test_client_vm_size               = var.private_test_client_vm_size
  } : name if value != null]
}

variable "enable_private_networking" {
  description = "Unsupported legacy input. Omit all legacy network/access/agent/client settings; this entry is not a private-only deployment."
  type        = bool
  default     = null
  validation {
    condition     = var.enable_private_networking == null && length(local.supplied_legacy_network_inputs) == 0
    error_message = "api2026gateway rejects legacy network inputs: ${join(", ", concat(var.enable_private_networking == null ? [] : ["enable_private_networking"], local.supplied_legacy_network_inputs))}. Do not load legacy/customer profiles or remove private requirements just to bypass this check. Only gateway_backend_subnet_id prepares supported outbound integration; private ingress remains unimplemented."
  }
}

variable "private_network_mode" {
  description = "Rejected legacy network-ownership input; omit it from this entry."
  type        = string
  default     = null
}

variable "existing_private_network" {
  description = "Rejected legacy network object; this sentinel accepts any shape only to report the unsupported input."
  type        = any
  default     = null
}

variable "private_dns_zone_group_management" {
  description = "Rejected legacy private-DNS ownership input; omit it from this entry."
  type        = string
  default     = null
}

variable "enable_private_hosted_agent" {
  description = "Rejected legacy private-agent input; omit it from this entry."
  type        = bool
  default     = null
}

variable "private_hosted_agent_runtime_principal_id" {
  description = "Rejected legacy private-agent identity input; omit it from this entry."
  type        = string
  default     = null
}

variable "enable_private_test_client" {
  description = "Rejected legacy private-client input; omit it from this entry."
  type        = bool
  default     = null
}

variable "enable_storage_private_endpoint" {
  description = "Rejected legacy Blob private-endpoint input; omit it from this entry."
  type        = bool
  default     = null
}

variable "storage_public_network_access" {
  description = "Rejected legacy storage-access input; this entry does not implement that private path."
  type        = string
  default     = null
}

variable "gateway_public_network_access" {
  description = "Rejected legacy gateway-access input; this entry does not implement private ingress."
  type        = string
  default     = null
}

variable "models_public_network_access" {
  description = "Rejected legacy model-access input; this entry does not implement that private path."
  type        = string
  default     = null
}

variable "gateway_private_endpoint_manual_approval" {
  description = "Rejected legacy private-endpoint approval input; omit it from this entry."
  type        = bool
  default     = null
}

variable "private_network_address_prefix" {
  description = "Rejected legacy network-creation input; this entry does not create a VNet."
  type        = string
  default     = null
}

variable "private_test_client_ssh_public_key" {
  description = "Rejected legacy test-client input; this entry does not create a test VM."
  type        = string
  default     = null
}

variable "private_test_client_vm_size" {
  description = "Rejected legacy test-client input; this entry does not create a test VM."
  type        = string
  default     = null
}

mock_provider "azapi" {}

variables {
  subscription_id             = "00000000-0000-0000-0000-000000000001"
  environment_name            = "private-wrapper-fixture"
  location                    = "swedencentral"
  gateway_location            = "swedencentral"
  api2026_resource_group_name = "single-fixture"
}

run "single_group_profile_reaches_child" {
  command = plan
  assert {
    condition = (
      output.gateway_contract.single_resource_group &&
      !output.gateway_contract.private_lab &&
      output.api2026_private_lab == null &&
      alltrue([for name in values(output.resource_groups) : name == var.api2026_resource_group_name])
    )
    error_message = "The real wrapper must forward the exact-name opt-in without silently enabling private resources."
  }
}

run "private_lab_profile_reaches_child_with_computed_ids" {
  command = plan
  variables {
    api2026_private_lab_enabled              = true
    api2026_private_lab_ssh_public_key       = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA synthetic-only"
    standalone_backend_public_network_access = "Disabled"
  }
  assert {
    condition = (
      output.gateway_contract.single_resource_group &&
      output.gateway_contract.private_lab &&
      alltrue([for access in values(output.backend_public_network_access) : access == "Disabled"]) &&
      length(output.api2026_private_lab.subnet_ids) == 3 &&
      length(output.api2026_private_lab.private_endpoints) == 5 &&
      length(output.api2026_private_lab.dns_zones) == 9 &&
      toset(keys(output.api2026_private_lab.identities)) == toset(["negative", "positive"])
    )
    error_message = "Private-lab mode must reach the real child and plan its full known inventory without pre-existing subnet or identity IDs."
  }
}

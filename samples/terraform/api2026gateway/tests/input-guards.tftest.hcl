# Isolate the entry-point input checks; the parent suite mocks full resource plans.
mock_provider "azapi" {}

override_module {
  target  = module.gateway
  outputs = {}
}

variables {
  subscription_id  = "00000000-0000-0000-0000-000000000001"
  location         = "eastus2"
  gateway_location = "swedencentral"
}

run "accept_new_entry_defaults" {
  command = plan
}

run "reject_legacy_private_enable" {
  command = plan
  variables {
    enable_private_networking = true
  }
  expect_failures = [var.enable_private_networking]
}

run "reject_even_public_legacy_profile_flag" {
  command = plan
  variables {
    enable_private_networking = false
  }
  expect_failures = [var.enable_private_networking]
}

run "reject_legacy_network_ownership" {
  command = plan
  variables {
    private_network_mode = "existing"
  }
  expect_failures = [var.enable_private_networking]
}

run "reject_legacy_platform_ids" {
  command = plan
  variables {
    existing_private_network = { gateway_subnet_id = "platform-owned" }
  }
  expect_failures = [var.enable_private_networking]
}

run "reject_legacy_dns_ownership" {
  command = plan
  variables {
    private_dns_zone_group_management = "platform"
  }
  expect_failures = [var.enable_private_networking]
}

run "reject_unimplemented_private_agents" {
  command = plan
  variables {
    enable_private_hosted_agent = true
  }
  expect_failures = [var.enable_private_networking]
}

run "reject_ignored_runtime_grant" {
  command = plan
  variables {
    private_hosted_agent_runtime_principal_id = "00000000-0000-0000-0000-000000000002"
  }
  expect_failures = [var.enable_private_networking]
}

run "reject_unimplemented_private_client" {
  command = plan
  variables {
    enable_private_test_client = true
  }
  expect_failures = [var.enable_private_networking]
}

run "reject_unimplemented_storage_endpoint" {
  command = plan
  variables {
    enable_storage_private_endpoint = true
  }
  expect_failures = [var.enable_private_networking]
}

run "reject_ignored_storage_access_posture" {
  command = plan
  variables {
    storage_public_network_access = "Disabled"
  }
  expect_failures = [var.enable_private_networking]
}

run "reject_ignored_gateway_access_posture" {
  command = plan
  variables {
    gateway_public_network_access = "Disabled"
  }
  expect_failures = [var.enable_private_networking]
}

run "reject_ignored_model_access_posture" {
  command = plan
  variables {
    models_public_network_access = "Disabled"
  }
  expect_failures = [var.enable_private_networking]
}

run "reject_unimplemented_endpoint_approval" {
  command = plan
  variables {
    gateway_private_endpoint_manual_approval = true
  }
  expect_failures = [var.enable_private_networking]
}

run "reject_ignored_network_prefix" {
  command = plan
  variables {
    private_network_address_prefix = "10.30.0.0/16"
  }
  expect_failures = [var.enable_private_networking]
}

run "reject_ignored_client_key" {
  command = plan
  variables {
    private_test_client_ssh_public_key = "ssh-ed25519 test-public-key"
  }
  expect_failures = [var.enable_private_networking]
}

run "reject_ignored_client_size" {
  command = plan
  variables {
    private_test_client_vm_size = "Standard_B2s_v2"
  }
  expect_failures = [var.enable_private_networking]
}

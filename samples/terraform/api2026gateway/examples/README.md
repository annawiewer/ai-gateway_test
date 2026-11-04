# Optional input examples

[model-routing.tfvars.example](model-routing.tfvars.example) illustrates complete
replacement model and alias maps. It is not automatically loaded, does not merge
with defaults, and is not a separate Terraform stack.

The primary new-lab template remains [terraform.tfvars.example](../terraform.tfvars.example)
in the entry directory. Retain complete approved inputs for an existing workload;
do not replace them with an example.

Follow the [deployment guide](../README.md) and
[map-replacement reference](../docs/reference.md#complete-map-replacement).
Run Terraform from the [entry directory](../), not this examples folder.

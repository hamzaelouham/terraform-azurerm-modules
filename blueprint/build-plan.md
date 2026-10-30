# Build Plan

List the features that make up your project, high level and in rough build order.
Keep each item to one line; the details come later in `/feature`.

Plain bullets are fine. When both planning docs are ready, run `/overview`.
It adds tracking numbers and checkboxes to your feature list before generating
the project overview.

Run `/feature` to spec the next unchecked item, or `/feature 2` to pick one.
Keep completed items checked and append new features as the project grows.
Do not renumber completed features; their archived specs refer to those IDs.

Scaffolding the app and prototyping its look are pre-build steps, not features.
Start with your first real slice of functionality.

## Your features

Seeded by `/adopt`. Checked items already exist in the repo.

- [x] 1. **resource-group module** - resource group with tags and `prevent_destroy`
- [x] 2. **vnet module** - virtual network, subnets, NSG and rules
- [x] 3. **key-vault module** - RBAC key vault with purge protection, access policies, network ACLs
- [x] 4. **service-principal module** - Entra ID app and SP with federated credentials and rotating secret
- [x] 5. **virtual-machine module** - Linux/Windows VM with NIC, public/private IP, data disks, identity, offline tests
- [x] 6. **storage-account module** - fill the empty `modules/storage-account`
  - [x] 6a. **Storage account core** - account with secure defaults, network rules, blob containers, file shares
  - [x] 6b. **Storage account private endpoint** - optional blob private endpoint into a vnet subnet

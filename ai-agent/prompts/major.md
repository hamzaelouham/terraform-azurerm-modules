# This is a new major version

- Read the upgrade guide at the end of `azurerm-release-notes.md`. Search for
  `# Upgrade guide for azurerm`. It lists what major version {major} removes and changes.
- In this module's `versions.tf`, raise the azurerm limit to this major:
  `>= {major}.0, < {next_major}.0`. Otherwise Verify keeps testing the old major.
- Under **Version bump**, a raised limit needs a major version bump, because it breaks
  the module's callers.

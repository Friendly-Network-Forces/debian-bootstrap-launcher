# Architecture

## Purpose

`debian-bootstrap-launcher` prepares a fresh Debian system for the private
`DebianBootstrap` workflow.

Its primary responsibilities are:

- Validate the operating system and execution context.
- Identify or create the permanent user account.
- Detect the permanent user's home-directory encryption state.
- Optionally configure `fscrypt` for an empty home directory.
- Refuse unsafe migration of a populated home directory.
- Prepare SSH access for cloning the private bootstrap repository.
- Hand off execution to the private DebianBootstrap installer.

The launcher must prioritize safety, explicit user choice, and clear recovery
paths over aggressive automation.

---

## Design Principles

### Safety first

The launcher must never:

- Delete a populated home directory.
- Attempt in-place encryption of an existing home directory.
- Enable ext4 encryption features on a mounted filesystem.
- Assume that a home directory is empty because the system is newly installed.
- Remove the temporary administrator automatically.
- Store passwords, recovery passphrases, or private keys in logs.
- Continue after a critical validation failure.

### State-aware behavior

The launcher must inspect the current system before making changes.

It should distinguish between:

1. Home directory already encrypted.
2. Home directory exists and is empty.
3. Home directory exists and contains data.
4. Home directory does not exist.
5. Underlying filesystem does not support the selected encryption workflow.
6. ext4 supports fscrypt but the `encrypt` feature is not enabled.

### Explicit consent

Encryption must be optional.

The default answer to destructive or security-sensitive prompts must be `No`.

### Idempotence

Where practical, the launcher should be safe to run more than once.

Examples:

- Installed packages should be detected and skipped.
- Existing PAM configuration should be recognized.
- Existing users should be reused rather than recreated.
- Existing encrypted home directories should be detected.
- Existing repository checkouts should be updated or left untouched according
  to user choice.

### Separation of concerns

The launcher should orchestrate system preparation only.

The private DebianBootstrap repository should remain responsible for:

- Dotfiles
- Desktop configuration
- Shell configuration
- Application installation
- User services
- Personal settings
- Host-specific customization

---

## Execution Model

The intended workflow uses two accounts:

### Temporary administrator

A temporary administrative account is created during Debian installation.

This account is used to:

- Clone the public launcher.
- Run the launcher with root privileges.
- Prepare the permanent user's encrypted home directory.
- Clone the private DebianBootstrap repository.
- Verify the permanent user's login.

The launcher must not automatically delete this account.

### Permanent user

The permanent user is the account that will own the configured system.

Example:

```text
smcenroe

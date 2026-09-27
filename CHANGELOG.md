# Changelog

All notable changes to this module are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html). Consumers pin the commit SHA of a release tag; see [Versioning and releases](README.md#versioning-and-releases).

## [Unreleased]

## [1.0.0] - 2026-09-24

Breaking release. One module call still provisions one key, but the policy is now composed from typed inputs, aliases are a set, and grants and multi-Region replicas are first-class. [docs/UPGRADE-1.0.md](docs/UPGRADE-1.0.md) maps every 0.1.x input to its replacement, lists what changes in place for an existing key, and gives the ready-to-paste `moved` block for the alias.

### Added

- Submodule `key-policy`: a pure renderer (no resources, no provider) that turns `enable_root_administration`, `key_administrator_arns`, `key_user_arns`, `key_service_principals`, and `statements` into a deterministic key policy document with the AWS-documented administrator and use action lists, grant management limited to AWS resources, conditions grouped by operator, and sorted principals, actions, resources, and values. Usable standalone from a Git source; tested without any provider.
- Submodule `replica`: one `aws_kms_replica_key` per call in the Region of the provider the caller passes, with its own aliases and a policy composed by the same renderer from the partition and account parsed out of `primary_key_arn`.
- Typed policy inputs on the root: `enable_root_administration`, `key_administrator_arns`, `key_user_arns`, `key_service_principals` (with per-principal actions and conditions), and `policy_statements` (keyed by Sid, with effect, typed principals, actions, resources, and conditions). An `Allow` to a wildcard principal must carry a condition.
- `policy_json_override` to apply a caller document verbatim; exclusive with the typed inputs.
- `aliases` as a set: one `aws_kms_alias.this["<name>"]` per name, validated against the KMS alias grammar and the reserved `aws/` prefix.
- `grants` map: one `aws_kms_grant.this["<name>"]` per entry with validated operations, `retiring_principal`, encryption-context `constraints`, `grant_creation_tokens`, and `retire_on_delete`; `grant_ids` and sensitive `grant_tokens` outputs.
- `rotation_period_in_days` (90 to 2560), `is_enabled`, `bypass_policy_lockout_safety_check`, and `custom_key_store_id`.
- `account_id` and `partition` inputs. The `aws_caller_identity` and `aws_partition` data sources run only when the corresponding input is null.
- Plan-time preconditions for the key spec and usage compatibility matrix, rotation support (`SYMMETRIC_DEFAULT` outside custom key stores only), `rotation_period_in_days` requiring rotation, custom key store constraints, and override exclusivity.
- Advisory `check` blocks: `root_administration_disabled` (no root statement and no administrators) and `rotation_disabled_for_symmetric_key`.
- Outputs `key_usage`, `key_spec`, `policy`, `alias_arns`, `alias_names`, `grant_ids`, `grant_tokens`, `multi_region`, `account_id`, and `partition`.
- `terraform test` suites for the root and both submodules; five executable examples (`minimal`, `complete`, `multi-region`, `asymmetric-signing`, `multiple-keys`).
- `docs/DESIGN.md`, `docs/UPGRADE-1.0.md`, submodule READMEs, `CONTRIBUTING.md`, `SECURITY.md`, and `LICENSE`.
- Credential-driven integration suite `tests/integration/smoke.tftest.hcl` with a disposable fixture module, `make integration-smoke`, a dispatch-only `integration` workflow that assumes a role through GitHub OIDC from the protected `integration` environment, and the IAM trust and permissions documents the role needs.
- Repository standards: `Makefile` quality gate, pre-commit configuration, tflint and terraform-docs configuration, Dependabot, CODEOWNERS, issue and pull request templates, a CI matrix over every directory with a docs drift check, and the `module-release` workflow.

### Changed

- **Breaking:** `alias_name` (one optional alias, `aws_kms_alias.this[0]`) is replaced by `aliases` (a set, `aws_kms_alias.this["<name>"]`). The `alias_arn` output is replaced by the `alias_arns` and `alias_names` maps.
- **Breaking:** `key_policy` is replaced by `policy_json_override` (same semantics) and the typed policy inputs.
- **Breaking:** `customer_master_key_spec` is renamed `key_spec`; the provider attribute underneath is unchanged, so the key is not replaced.
- **Breaking:** `key_usage` and `key_spec` are validated enums, and rotation is rejected at plan time for specs that do not support it. Asymmetric and HMAC keys must declare `enable_key_rotation = false`.
- **Breaking:** the default policy statement is rendered by the renderer with Sid `EnableRootAccess` and list-valued fields instead of Sid `EnableRootUserPermissions` with string-valued fields. Same permissions; an existing default key sees one in-place policy update.
- `description` is validated as 1 to 8192 characters.
- The module adds a `Name` tag (the first alias in sorted order, or the description) unless the caller sets one. Caller tags are never overridden.

### Removed

- **Breaking:** the unconditional `aws_partition` and `aws_caller_identity` reads. Both remain only as a fallback for null `partition` and `account_id`.

### Fixed

- Rotation enabled on an asymmetric or HMAC key, or a key in a custom key store, failed at apply time. It is now rejected at plan time with a message naming the spec.
- Incompatible `key_usage` and key spec combinations failed at apply time. The AWS compatibility matrix is checked at plan time.
- Renaming the single alias replaced `aws_kms_alias.this[0]`. Each alias now has its own address, so adding, removing, or renaming one never touches the others.

## [0.1.2] - 2026-09-22

### Changed

- The committed provider lock file carries checksums for Linux and macOS on amd64 and arm64, so `terraform init` on any supported runner leaves it unchanged.
- CI validates modules that declare provider configuration aliases through their test files instead of a standalone `terraform validate`.

## [0.1.1] - 2026-09-22

### Added

- Generated module reference (requirements, providers, resources, inputs, outputs) in the README.

## [0.1.0] - 2026-09-22

### Added

- Versioned module for one customer-managed KMS key with an optional alias, a caller-supplied `key_policy` or a root-only default policy, rotation on, and a 30-day deletion window.

[Unreleased]: https://github.com/hatan4ik/aws.modules.ksm/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/hatan4ik/aws.modules.ksm/compare/v0.1.2...v1.0.0
[0.1.2]: https://github.com/hatan4ik/aws.modules.ksm/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/hatan4ik/aws.modules.ksm/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/hatan4ik/aws.modules.ksm/releases/tag/v0.1.0

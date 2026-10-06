# Changelog

All notable changes to this module are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html). Consumers pin the commit SHA of a release tag; see [Versioning and releases](README.md#versioning-and-releases).

## [Unreleased]

**Major version bump (2.0.0).** `modules/replica` input `key_usage` no longer has a default. Root-module callers that do not use `modules/replica` are unaffected by that change; see the migration note below.

### Changed

- **Breaking (`modules/replica`):** `key_usage` is now a required input with no default (it previously defaulted to `ENCRYPT_DECRYPT`). A replica always inherits its primary's real cryptographic usage; this input only selects the use actions the replica policy grants. With the old default, a replica of a `SIGN_VERIFY`, `GENERATE_VERIFY_MAC`, or `KEY_AGREEMENT` primary whose caller forgot the input granted `key_user_arns` and default-action service principals Encrypt/Decrypt instead of the primary's actions. KMS accepts such a policy, plan and apply succeed, and the mismatch surfaced only when the replica was used, typically during a failover.

  **Migration.** Every `modules/replica` call must now set `key_usage`. Set it to the primary's usage, ideally from the same value the primary uses (a shared local, or `module.<primary>.key_usage`):

  ```hcl
  locals {
    key_usage = "ENCRYPT_DECRYPT" # the value the primary already uses
  }

  module "primary" {
    # ...
    key_usage = local.key_usage
  }

  module "replica" {
    # ...
    key_usage = local.key_usage
  }
  ```

  A caller that relied on the default for an `ENCRYPT_DECRYPT` primary sets `key_usage = "ENCRYPT_DECRYPT"` and sees no plan change. A caller whose primary is not `ENCRYPT_DECRYPT` was running with a wrong replica policy: setting the correct value shows an in-place policy update on `aws_kms_replica_key.this` that swaps the granted use actions. Review it, and apply it, before relying on the replica.
- `modules/key-policy` is now the single owner of the `statements` / `policy_statements` and `key_service_principals` validations. The root previously duplicated all ten of them and the replica two, with differently worded messages. The rules themselves are unchanged and still fail at plan time; the error is now reported by `modules/key-policy` against the caller's line that passes the input, and its messages name both `statements` and `policy_statements`. A root test that used `expect_failures = [var.policy_statements]` or `[var.key_service_principals]` for these rules no longer sees the failure on the root variable.
- `policy_json_override` (root and replica) must now carry a `Statement` element, not just parse as JSON, matching `aws.modules.s3`. A document without `Statement` was always rejected by KMS at apply; it now fails at plan.
- `examples/multi-region` declares `key_usage` and every policy input once in `locals` and passes the same values to the primary and the replica, and exposes `primary_policy` and `replica_policy` outputs.

### Added

- `service_grants` (root, `modules/replica`, `modules/key-policy`): typed presets that render the AWS-documented minimum key policy grant for three integrations, keyed by Sid, from the ARN of the resource the grant is for. Additive and optional; an empty map (the default) renders exactly the policy it rendered before. See [docs/DESIGN.md](docs/DESIGN.md#service-grant-presets).
  - `cloudwatch-logs`: `logs.<region>.<dns_suffix>` gets `kms:Encrypt`, `kms:Decrypt`, `kms:ReEncrypt*`, `kms:GenerateDataKey*`, `kms:Describe*`, scoped by `ArnEquals` (or `ArnLike` for a `*` pattern) on `kms:EncryptionContext:aws:logs:arn` to the log group.
  - `cloudfront`: `cloudfront.amazonaws.com` gets `kms:Decrypt`, scoped by `AWS:SourceArn` to one distribution; identical to `aws.modules.cloudfront`'s `required_kms_key_policy_json`.
  - `secretsmanager`: the caller principals in `principal_arns` (Secrets Manager calls KMS with the caller's identity, not a service principal) get `kms:Decrypt`, `kms:Encrypt`, `kms:GenerateDataKey`, scoped by `kms:ViaService` to Secrets Manager in the secret's Region and by `kms:EncryptionContext:SecretARN` to the secret (`StringLike` for a `name-??????` pattern).
  - Plan-time rules: `service` enum, ARN format per service (no wildcard distribution, no trailing `:*` on a log group), `principal_arns` required for `secretsmanager` and rejected otherwise, Sids unique across `service_grants`, `policy_statements`, and the generated statements, `resource_arn` in the key's partition, an `ENCRYPT_DECRYPT` key, and (root) a `SYMMETRIC_DEFAULT` key spec.
- `dns_suffix` input on `modules/key-policy`, required only by the regional presets. The root and `modules/replica` read it from `aws_partition`, as `aws.modules.ecs` does. `aws_partition` now also runs in the root when `partition` is declared, and in the replica, but only when a `cloudwatch-logs` or `secretsmanager` preset is present; it makes no API call, and a precondition requires its partition to match the declared (root) or `primary_key_arn` (replica) partition.
- Advisory `check` `policy_lockout_safety_check_bypassed` in the root and `modules/replica`: warns on every plan and apply while `bypass_policy_lockout_safety_check = true`, the one setting whose misuse can lock a key until AWS Support recovers it. Non-blocking, like the existing checks.
- `modules/key-policy` fails the plan when the rendered policy exceeds the KMS key policy limit of 32 KB (32,768 bytes, measured in UTF-8 bytes) instead of letting KMS reject it at apply. New output `size_bytes`.
- `tests/multi_region_example.tftest.hcl` applies `examples/multi-region` against mock providers (nothing is created) and fails if the primary's and the replica's rendered policies differ.
- README, `modules/replica/README.md`, and `docs/DESIGN.md` document that multi-Region primaries and replicas keep independent key policies and that keeping them in sync is the caller's responsibility. `docs/DESIGN.md` no longer claims the replica is created "with the same policy inputs" as the root.

### Fixed

- The `Name` tag falls back to the description when no alias is declared, but `description` allows 8192 characters while AWS caps tag values at 256. A description over 256 characters passed plan and failed at apply. The fallback is now truncated to the first 256 characters (root and replica); the key description itself is unchanged.
- Stale version comments on the pinned actions in `.github/workflows/integration.yml` (`actions/checkout` is v7.0.1, `aws-actions/configure-aws-credentials` is v6.3.0).

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

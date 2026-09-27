# Design: aws.modules.ksm v1

Status: accepted 2026-09-23. Supersedes the v0.1.x "raw policy string" design.

The repository is named `ksm` for historical reasons and keeps that name. The
module it contains manages AWS Key Management Service (KMS) resources and is
documented as "aws.modules.ksm (AWS KMS)".

## Purpose

`aws.modules.ksm` provisions **one** customer-managed KMS key per module call
together with the resources a key cannot be used without: a composed key
policy, aliases, and grants. A separate submodule provisions a multi-Region
replica of that key in another Region with its own policy and aliases. The
module is secure by default (rotation on, a 30-day deletion window, a policy
that always names a principal), explicit by declaration (administrators, users,
service principals, and extra statements are typed inputs), and composable
(the policy renderer is a pure submodule that can be used on its own, and the
whole policy can be replaced by a caller-supplied document without changing
the module's outputs).

The module deliberately does **not** create IAM roles, log groups, buckets,
secrets, or any resource that is encrypted with the key. Those have separate
lifecycles and owners. The module consumes their principals' ARNs and exposes
the key's identifiers for them to reference.

## Why the v0.1.x design was replaced

| v0.1.x behaviour | Problem | v1 decision |
|---|---|---|
| The key policy is either a raw `key_policy` JSON string or a root-only default. | Every consumer re-implements the AWS administrator and user statements by hand, differently; the module cannot validate or test what it applies; a mistake locks the key. | Typed policy inputs (`key_administrator_arns`, `key_user_arns`, `key_service_principals`, `policy_statements`) rendered by the pure `key-policy` submodule into a deterministic document. `policy_json_override` remains for callers who must supply the whole document. |
| One optional alias through `alias_name`. | Keys commonly carry several aliases (a stable name and a versioned name); the `count`-indexed resource makes renaming an alias a replacement of `[0]`. | `aliases` is a set; each alias is `aws_kms_alias.this["<name>"]`, so adding or removing one never touches the others. |
| No grants. | Services that use grants (EBS, RDS, Lambda, cross-account integrations) needed a second module or hand-written resources with unvalidated operation names. | A typed `grants` map with validated operations, encryption-context constraints, and a sensitive `grant_tokens` output. |
| No multi-Region replicas. | `multi_region = true` created a primary that nothing could replicate. | `modules/replica` creates `aws_kms_replica_key` in the Region of the provider the caller passes, with the same policy inputs and aliases as the root. |
| No rotation period; `enable_key_rotation` accepted for every key spec. | Rotation on an asymmetric or HMAC key fails at apply time; the rotation period could not be shortened from the 365-day default. | `rotation_period_in_days` (90 to 2560) and a plan-time precondition that allows rotation only on `SYMMETRIC_DEFAULT` keys outside custom key stores. |
| `key_usage` and `customer_master_key_spec` were free-form strings. | Incompatible combinations (an HMAC spec with `ENCRYPT_DECRYPT`, an ECC spec with `ENCRYPT_DECRYPT`) failed at apply time. | Both are validated enums and a precondition checks the AWS compatibility matrix at plan time. `customer_master_key_spec` is renamed `key_spec`, the name AWS uses today. |
| Partition and account were always read through data sources. | Every plan performed two API reads, and a consumer that already knew the values could not pass them in. | `account_id` and `partition` are inputs. The data sources run only when an input is null, which is the one documented exception to the no-data-source rule. |
| No tests, no examples. | Behaviour was unverifiable and undocumented. | `terraform test` suites for the root and both submodules, five executable examples, and CI that validates every directory. |

## Principles and how the module applies them

- **Single responsibility.** `modules/key-policy` owns the shape of a KMS
  key policy and nothing else: no resources, no provider. `modules/replica`
  owns a replica key and its aliases. The root owns the primary key, its
  aliases, and its grants, and composes the policy renderer.
- **Open/closed.** New access is added by declaring data (an administrator,
  a user, a service principal with conditions, a statement, an alias, a
  grant), not by editing the module. The whole policy can be swapped for a
  caller document through `policy_json_override`.
- **Liskov substitution.** A caller-supplied policy is a drop-in for the
  composed one; outputs (`policy`, `arn`, `key_id`, alias and grant maps) are
  identical. A replica key exposes the same identifier outputs as the
  primary.
- **Interface segregation.** Feature groups are optional and default to
  empty. A minimal key needs only `description`. Policy, alias, grant, and
  replica concerns are separate inputs and separate submodules.
- **Dependency inversion.** The root depends on principal ARNs and account
  identifiers, never on how they were produced. The replica derives the
  partition and account from `primary_key_arn` and performs no lookups.
- **Clean, deterministic code.** Statements, principals, actions, resources,
  and condition values are sorted; conditions are grouped by operator; null
  and empty attributes never render. Every rule fails at plan time with a
  message that names the input to change.

## Architecture

```text
root (one key)
├── modules/key-policy             pure: typed inputs -> key policy JSON (no resources, no provider)
├── data.aws_partition.current     only when partition is null
├── data.aws_caller_identity       only when account_id is null
├── aws_kms_key.this               spec/usage matrix, rotation, deletion window, multi-Region flag
├── aws_kms_alias.this[alias]      one resource per alias
└── aws_kms_grant.this[name]       one resource per grant, sensitive grant tokens

modules/replica (one replica key, provider passed by the caller)
├── modules/key-policy             the same renderer, partition and account parsed from primary_key_arn
├── aws_kms_replica_key.this
└── aws_kms_alias.this[alias]
```

Data flow: the root resolves `partition` and `account_id` (inputs first, data
sources only as a fallback), hands them with the policy inputs to
`key-policy`, and puts the rendered JSON on the key unless
`policy_json_override` is set, in which case the renderer is not instantiated
at all. Aliases and grants reference the key's `key_id`, so they are created
after the key and destroyed before it.

### Key policy renderer

The renderer produces at most five kinds of statement, in this order, each
present only when its input is non-empty:

| Sid | Principal | Actions | Condition |
|---|---|---|---|
| `EnableRootAccess` | `arn:<partition>:iam::<account>:root` | `kms:*` | none |
| `AllowKeyAdministration` | `key_administrator_arns` | The AWS-documented administrator list: `kms:Create*`, `kms:Describe*`, `kms:Enable*`, `kms:List*`, `kms:Put*`, `kms:Update*`, `kms:Revoke*`, `kms:Disable*`, `kms:Get*`, `kms:Delete*`, `kms:TagResource`, `kms:UntagResource`, `kms:ScheduleKeyDeletion`, `kms:CancelKeyDeletion`, `kms:RotateKeyOnDemand`, plus `kms:ReplicateKey` for multi-Region keys | none |
| `AllowKeyUse` | `key_user_arns` | The use actions for the key's `key_usage`: `kms:Encrypt`, `kms:Decrypt`, `kms:ReEncrypt*`, `kms:GenerateDataKey*`, `kms:DescribeKey` for `ENCRYPT_DECRYPT`; `kms:Sign`, `kms:Verify`, `kms:GetPublicKey`, `kms:DescribeKey` for `SIGN_VERIFY`; `kms:GenerateMac`, `kms:VerifyMac`, `kms:DescribeKey` for `GENERATE_VERIFY_MAC`; `kms:DeriveSharedSecret`, `kms:GetPublicKey`, `kms:DescribeKey` for `KEY_AGREEMENT` | none |
| `AllowAttachmentOfPersistentResources` | `key_user_arns` | `kms:CreateGrant`, `kms:ListGrants`, `kms:RevokeGrant` | `Bool kms:GrantIsForAWSResource = true` |
| `AllowServiceUse<Principal>` | one service principal each | the use actions above unless the entry overrides `actions` | the entry's `conditions` |
| `<Sid>` from `policy_statements` | the entry's typed `principals` | the entry's `actions` | the entry's `conditions` |

The renderer requires at least one statement: a key policy with none is
rejected by KMS and would lock the key. Statement Sids declared by the caller
may not collide with the generated ones.

### Root interface (summary)

Required: `description`.

Optional groups (all default to a safe value):

- Key: `key_usage`, `key_spec`, `enable_key_rotation`,
  `rotation_period_in_days`, `deletion_window_in_days`, `multi_region`,
  `is_enabled`, `bypass_policy_lockout_safety_check`, `custom_key_store_id`.
- Policy: `account_id`, `partition`, `enable_root_administration`,
  `key_administrator_arns`, `key_user_arns`, `key_service_principals`,
  `policy_statements`, or `policy_json_override` instead of all of them.
- Aliases: `aliases`.
- Grants: `grants`.
- `tags`.

Outputs expose every identifier a caller may need: `key_id`, `arn`,
`key_usage`, `key_spec`, `policy`, `alias_arns`, `alias_names`, `grant_ids`,
`grant_tokens` (sensitive), `multi_region`, `account_id`, `partition`.

### Lifecycle rules

- `deletion_window_in_days` only matters on destroy: the key is scheduled for
  deletion and stays recoverable for that many days. Aliases and grants are
  destroyed immediately.
- Disabling `enable_key_rotation` on an existing key stops future rotations;
  it does not remove past key material.
- `multi_region` is immutable on the key. Changing it replaces the key.
  `key_spec`, `key_usage`, and `custom_key_store_id` are likewise immutable.
- A grant's `retire_on_delete` decides whether Terraform retires or revokes
  the grant on destroy. Retiring is the cooperative path; revoking is
  immediate.

## Security defaults

- Rotation enabled on every symmetric key; the module refuses to configure
  rotation where AWS would reject it.
- A 30-day deletion window, the maximum AWS allows, so an accidental destroy
  can be cancelled.
- The key policy always names at least one principal; by default the account
  root, which keeps the key manageable through IAM. Disabling root
  administration without naming an administrator triggers an advisory
  `check`, because it is the standard way to lock a key.
- `bypass_policy_lockout_safety_check` stays false: KMS verifies that the
  caller can still administer the key before applying the policy.
- Users receive only the use actions that their key type supports, and grant
  management only for AWS-resource grants (`kms:GrantIsForAWSResource`).
- Service principals receive the use actions only under the conditions the
  caller declares (for example an encryption-context ARN for CloudWatch Logs).
- Grants validate their operations against the KMS operation list, and grant
  tokens are marked sensitive.
- Every principal ARN, alias name, statement Sid, and identifier is validated
  at plan time.

## Testing strategy

- Contract tests use `mock_provider` with `command = plan`; no credentials.
  Data-source fallbacks are given `mock_data` defaults so the rendered policy
  is fully known.
- `modules/key-policy/tests` cover the rendered document without any
  provider: defaults, each statement kind, condition grouping, sorting,
  service-principal Sids, Sid collisions, and the no-statement precondition.
- `modules/replica/tests` cover the replica key, its derived partition and
  account, its aliases, and its validations.
- Root `tests/` cover: secure defaults, every variable validation via
  `expect_failures`, policy composition through the root inputs, override
  exclusivity, the spec/usage matrix, rotation rules, aliases, grants, the
  data-source fallback, and both advisory checks.
- Every example is initialised and validated in CI; examples are the
  documentation's executable form.
- Static policy: `tflint` with the AWS ruleset, Checkov, Trivy; generated
  docs are checked for drift.

## Compatibility

- Terraform `>= 1.7.0, < 2.0.0` (the consuming platform pins 1.7.5).
- AWS provider `>= 6.35.0, < 7.0.0`.
- Key specs: `SYMMETRIC_DEFAULT`, `RSA_2048/3072/4096`,
  `ECC_NIST_P256/P384/P521`, `ECC_SECG_P256K1`, `HMAC_224/256/384/512`,
  `ML_DSA_44/65/87`. External key stores (`xks_key_id`) and the China-only
  `SM2` spec are roadmap items and will be added without breaking this
  interface.

## Migration

`docs/UPGRADE-1.0.md` maps every v0.1.x input to its v1 equivalent, lists the
settings that keep the key and its alias in place, explains the one in-place
policy update a default v0.1.x key sees, and gives `moved` blocks so a
consumer can adopt v1 without recreating the key or its alias.

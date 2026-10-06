# Design: aws.modules.kms v1

Status: accepted 2026-09-23. Supersedes the v0.1.x "raw policy string" design.

The repository was created as `aws.modules.ksm` and renamed to
`aws.modules.kms` on 2026-10-06. GitHub redirects the old URL and keeps every
tag and commit, so existing `?ref=<commit-sha>` pins keep resolving; new pins
should use the new URL. The resource names of the integration fixture keep the
`ksm-it` prefix, which the integration role's permissions are scoped to.

## Purpose

`aws.modules.kms` provisions **one** customer-managed KMS key per module call
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
| No multi-Region replicas. | `multi_region = true` created a primary that nothing could replicate. | `modules/replica` creates `aws_kms_replica_key` in the Region of the provider the caller passes, accepting the same *kinds* of policy inputs and aliases as the root. The values are the caller's to pass; nothing compares them with the primary's (see [Multi-Region policy parity](#multi-region-policy-parity)). |
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
  partition and account from `primary_key_arn`; its only lookup is
  `aws_partition`, for the DNS suffix of a regional `service_grants` preset.
- **Clean, deterministic code.** Statements, principals, actions, resources,
  and condition values are sorted; conditions are grouped by operator; null
  and empty attributes never render. Every rule fails at plan time with a
  message that names the input to change.

## Architecture

```text
root (one key)
├── modules/key-policy             pure: typed inputs -> key policy JSON (no resources, no provider)
├── data.aws_partition.current     only when partition is null, or a regional service_grants preset needs dns_suffix
├── data.aws_caller_identity       only when account_id is null
├── aws_kms_key.this               spec/usage matrix, rotation, deletion window, multi-Region flag
├── aws_kms_alias.this[alias]      one resource per alias
└── aws_kms_grant.this[name]       one resource per grant, sensitive grant tokens

modules/replica (one replica key, provider passed by the caller)
├── modules/key-policy             the same renderer, partition and account parsed from primary_key_arn
├── data.aws_partition.current     only when a regional service_grants preset needs dns_suffix
├── aws_kms_replica_key.this
└── aws_kms_alias.this[alias]
```

Data flow: the root resolves `partition` and `account_id` (inputs first, data
sources only as a fallback), hands them with the policy inputs to
`key-policy`, and puts the rendered JSON on the key unless
`policy_json_override` is set, in which case the renderer is not instantiated
at all. Aliases and grants reference the key's `key_id`, so they are created
after the key and destroyed before it.

### Multi-Region policy parity

A multi-Region primary and each of its replicas carry **independent** key
policies. KMS does not copy the primary's policy to a replica and never
compares them, and neither does this module: `modules/replica` receives its
own policy inputs and cannot read the primary's without a lookup, which the
replica deliberately does not perform. A replica whose policy differs from the
primary's plans and applies cleanly; the difference shows up only when a
principal uses the key in the replica's Region, usually during a failover.

Keeping the policies in sync is therefore the caller's responsibility. The
supported pattern, demonstrated by `examples/multi-region` and guarded by
`tests/multi_region_example.tftest.hcl` (which applies the example against
mock providers and requires the two rendered policies to be equal), is to
declare `key_usage` and every policy input once in `locals` and pass the same
values to the root and every replica call.

`key_usage` on the replica has no default. A replica always has its primary's
cryptographic usage; the input only selects which use actions the replica
policy grants. A default of `ENCRYPT_DECRYPT` on a replica of a `SIGN_VERIFY`
primary would grant Encrypt and Decrypt instead of Sign and Verify, which KMS
accepts without complaint. Requiring the value makes every caller state it.

### Validation ownership

`modules/key-policy` is the single owner of the policy rules for
`statements`, `key_service_principals`, and `service_grants`. The root and the
replica pass `policy_statements`, `key_service_principals`, and
`service_grants` through to it without
re-validating them, so the three modules cannot drift apart; Terraform reports
a failure against the caller's line that passes the input. Inputs that the
renderer does not see or that the root and replica use for other purposes
(principal ARNs, aliases, grants, `policy_json_override`) are validated where
they are declared.

### Key policy renderer

The renderer produces at most six kinds of statement, in this order, each
present only when its input is non-empty:

| Sid | Principal | Actions | Condition |
|---|---|---|---|
| `EnableRootAccess` | `arn:<partition>:iam::<account>:root` | `kms:*` | none |
| `AllowKeyAdministration` | `key_administrator_arns` | The AWS-documented administrator list: `kms:Create*`, `kms:Describe*`, `kms:Enable*`, `kms:List*`, `kms:Put*`, `kms:Update*`, `kms:Revoke*`, `kms:Disable*`, `kms:Get*`, `kms:Delete*`, `kms:TagResource`, `kms:UntagResource`, `kms:ScheduleKeyDeletion`, `kms:CancelKeyDeletion`, `kms:RotateKeyOnDemand`, plus `kms:ReplicateKey` for multi-Region keys | none |
| `AllowKeyUse` | `key_user_arns` | The use actions for the key's `key_usage`: `kms:Encrypt`, `kms:Decrypt`, `kms:ReEncrypt*`, `kms:GenerateDataKey*`, `kms:DescribeKey` for `ENCRYPT_DECRYPT`; `kms:Sign`, `kms:Verify`, `kms:GetPublicKey`, `kms:DescribeKey` for `SIGN_VERIFY`; `kms:GenerateMac`, `kms:VerifyMac`, `kms:DescribeKey` for `GENERATE_VERIFY_MAC`; `kms:DeriveSharedSecret`, `kms:GetPublicKey`, `kms:DescribeKey` for `KEY_AGREEMENT` | none |
| `AllowAttachmentOfPersistentResources` | `key_user_arns` | `kms:CreateGrant`, `kms:ListGrants`, `kms:RevokeGrant` | `Bool kms:GrantIsForAWSResource = true` |
| `AllowServiceUse<Principal>` | one service principal each | the use actions above unless the entry overrides `actions` | the entry's `conditions` |
| `<Sid>` from `service_grants` | the preset's grantee | the preset's documented actions | the preset's documented conditions; see [Service grant presets](#service-grant-presets) |
| `<Sid>` from `policy_statements` | the entry's typed `principals` | the entry's `actions` | the entry's `conditions` |

The renderer requires at least one statement: a key policy with none is
rejected by KMS and would lock the key. Statement Sids declared by the caller
may not collide with the generated ones. The rendered document must also fit
the KMS key policy limit of 32 KB (32,768 bytes); the renderer measures it in
UTF-8 bytes and fails the plan when it is larger, rather than letting KMS
reject it at apply.

### Service grant presets

`key_service_principals` and `policy_statements` can express any grant, which
also means every consumer had to re-derive the same three statements by hand:
CloudWatch Logs for encrypted log groups, CloudFront origin access control for
an S3 origin encrypted with SSE-KMS, and Secrets Manager for secrets under a
customer managed key. Each has a non-obvious detail that a hand-written
statement gets wrong (a regional principal, an encryption-context key, a
grantee that is not a service principal). `service_grants` renders each one
from the minimum the caller must know: the resource the grant is for.

```hcl
service_grants = {
  OrdersLogs = { service = "cloudwatch-logs", resource_arn = "arn:aws:logs:us-east-1:123456789012:log-group:/aws/ecs/orders" }
  OrdersCdn  = { service = "cloudfront", resource_arn = "arn:aws:cloudfront::123456789012:distribution/E2QWRUHAPOMQZL" }
  OrdersDb = {
    service        = "secretsmanager"
    resource_arn   = "arn:aws:secretsmanager:us-east-1:123456789012:secret:orders/db-??????"
    principal_arns = ["arn:aws:iam::123456789012:role/orders-task"]
  }
}
```

| `service` | Grantee | Actions | Condition | AWS source |
|---|---|---|---|---|
| `cloudwatch-logs` | `Service: logs.<region>.<dns_suffix>` | `kms:Encrypt`, `kms:Decrypt`, `kms:ReEncrypt*`, `kms:GenerateDataKey*`, `kms:Describe*` | `ArnEquals` (`ArnLike` when the ARN has `*`) on `kms:EncryptionContext:aws:logs:arn` = `resource_arn` | CloudWatch Logs User Guide, *Encrypt log data in CloudWatch Logs using AWS KMS*, step 2 |
| `cloudfront` | `Service: cloudfront.amazonaws.com` | `kms:Decrypt` | `StringEquals AWS:SourceArn` = `resource_arn` | CloudFront Developer Guide, *Restrict access to an Amazon S3 origin*, SSE-KMS; identical to `aws.modules.cloudfront`'s `required_kms_key_policy_json` |
| `secretsmanager` | `AWS: principal_arns` | `kms:Decrypt`, `kms:Encrypt`, `kms:GenerateDataKey` | `StringEquals kms:ViaService` = `secretsmanager.<region>.<dns_suffix>`; `StringEquals` (`StringLike` when the ARN has `?` or `*`) on `kms:EncryptionContext:SecretARN` = `resource_arn` | Secrets Manager User Guide, *Secret encryption and decryption*: permissions for the KMS key, how Secrets Manager uses the key, encryption context |

Why each preset is shaped the way it is:

- **CloudWatch Logs.** The action list is the one AWS documents, verbatim
  (`kms:Encrypt` and `kms:Decrypt`, not `Encrypt*`/`Decrypt*`). The principal
  is regional and AWS requires it to be in the key's Region. The principal is
  built as `logs.<region>.<dns_suffix>`, the same expression
  `aws.modules.ecs` uses (`logs.${region}.${data.aws_partition.current.dns_suffix}`),
  so it is correct in `aws-cn` (`amazonaws.com.cn`). CloudWatch Logs sends the
  log group ARN as encryption context on every call; AWS's example for one log
  group uses `ArnEquals`, and its example for a pattern uses `ArnLike`, which
  is what the preset selects. The ARN is the bare log group ARN: a trailing
  `:*` (the form the `DescribeLogGroups` API returns; the AWS provider's
  `aws_cloudwatch_log_group.arn` strips it) never matches the encryption
  context and is rejected.
- **CloudFront.** AWS's generic example grants `kms:Decrypt`,
  `kms:Encrypt`, and `kms:GenerateDataKey*` because OAC can also forward
  `PUT`. The platform's `aws.modules.cloudfront` only reads
  (`s3:GetObject` in its bucket statement), so the preset grants
  `kms:Decrypt` only, matching that module's output exactly. A distribution
  that writes through OAC needs the extra two actions in a
  `policy_statements` entry. The distribution ARN may not contain a wildcard:
  the distribution ID is what stops every other distribution, in any account,
  from decrypting through the shared service principal. OAC exists only in
  the `aws` partition, so other partitions are rejected.
- **Secrets Manager.** Secrets Manager does **not** call KMS as
  `secretsmanager.amazonaws.com`: "it acts on behalf of the user who is
  accessing or updating the secret value", and CloudTrail records the caller
  as the identity with `invokedBy: secretsmanager.amazonaws.com`. A key policy
  statement for the `secretsmanager.amazonaws.com` service principal grants
  nothing useful. The grantee is therefore the caller (`principal_arns`,
  required for this preset and rejected for the other two), restricted the
  way AWS restricts its own `aws/secretsmanager` key: `kms:ViaService` for
  Secrets Manager in the secret's Region. The preset adds the encryption
  context AWS documents, `SecretARN`, so the grant covers one secret rather
  than every secret on the key. The actions are the operations Secrets Manager
  calls with that encryption context: `GenerateDataKey` (create and put a
  value, and the access validation when a key is set), `Decrypt` (get a
  value, idempotency check, replication), and `Encrypt` (re-encrypting the
  data keys when a secret is moved onto this key with `UpdateSecret`, and
  replication). `kms:DescribeKey` is left out: Secrets Manager calls it only so
  the console can list keys, without an encryption context, so it could never
  satisfy this statement's condition. `kms:CallerAccount`, used by the
  `aws/secretsmanager` policy because its principal is `*`, is redundant with
  explicit principals and would break a cross-account reader, so it is not
  added. A secret's ARN ends in a random six-character suffix that does not
  exist until the secret does, and the secret needs the key first; `?` and
  `*` are therefore allowed (`name-??????`) and switch the `SecretARN`
  condition to `StringLike`, which keeps the key policy free of a dependency on
  the secret.

Why this interface:

- **One map, keyed by Sid, like `policy_statements`.** The key is the
  statement's Sid, so a grant is addressed and diffed by a name the caller
  chose, several grants of the same service coexist (one per log group or
  secret), and a Sid collision with `policy_statements` or a generated Sid
  fails at plan.
- **`service` is a validated enum, not three separate variables.** One
  variable keeps the presets discoverable in one place and lets new presets
  be added as new enum values without growing the root, replica, and renderer
  interfaces three times.
- **No `region` field.** The Region, account, and partition are read from
  `resource_arn`, which already carries them. A separate `region` could
  disagree with the ARN and render a principal in one Region and a condition
  in another; deriving it makes that impossible.
- **Fields that do not apply are rejected, not ignored.** `principal_arns` on
  a service-principal preset is an error rather than silently dropped, so a
  caller who expected it to restrict the grant finds out at plan.
- **The DNS suffix comes from the provider, not a table.** The renderer is
  pure and takes `dns_suffix` as an input (required only by the regional
  presets). The root and the replica read it from `aws_partition`, which
  makes no API call. This adds a conditional lookup to the replica, which
  otherwise performs none, and runs the root's `aws_partition` even when
  `partition` is passed; a precondition then requires the declared or
  ARN-derived partition to match the provider's, so the suffix cannot come
  from a different partition than the key.
- **Plan-time rules.** Variable validations check each entry on its own
  (Sid, `service`, the ARN format for that service, `principal_arns`).
  Rules that span inputs are output preconditions in the renderer: the key
  must be `ENCRYPT_DECRYPT`, `resource_arn` must be in the key's partition,
  `dns_suffix` must be set for a regional preset, and Sids must not collide
  with `statements`. The root adds a precondition that the key spec is
  `SYMMETRIC_DEFAULT`, since all three services accept only symmetric
  encryption keys.
- **Multi-Region.** Pass the same `service_grants` to the primary and every
  replica to keep the policies identical. A regional preset names the
  Region of its `resource_arn`, so it takes effect only on the key in that
  Region, which is also the only key CloudWatch Logs or Secrets Manager there
  would use.

### Root interface (summary)

Required: `description`.

Optional groups (all default to a safe value):

- Key: `key_usage`, `key_spec`, `enable_key_rotation`,
  `rotation_period_in_days`, `deletion_window_in_days`, `multi_region`,
  `is_enabled`, `bypass_policy_lockout_safety_check`, `custom_key_store_id`.
- Policy: `account_id`, `partition`, `enable_root_administration`,
  `key_administrator_arns`, `key_user_arns`, `key_service_principals`,
  `service_grants`, `policy_statements`, or `policy_json_override` instead of
  all of them.
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
  caller can still administer the key before applying the policy. Setting it
  to true raises the advisory `policy_lockout_safety_check_bypassed` check
  (root and replica) on every plan and apply.
- When the description stands in for the `Name` tag it is truncated to 256
  characters, the AWS tag value limit, so a long but valid description never
  fails at apply.
- `policy_json_override` must parse as JSON and carry a `Statement` element,
  matching `aws.modules.s3`.
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
  service-principal Sids, Sid collisions, every `statements` and
  `key_service_principals` validation, the no-statement precondition, and the
  32 KB size precondition. `service_grants.tftest.hcl` pins each preset's
  rendered statement against the AWS-documented grant, the `ArnLike` and
  `StringLike` switches, ordering, and every `service_grants` validation and
  precondition.
- `modules/replica/tests` cover the replica key, its derived partition and
  account, its aliases, and its validations.
- Root `tests/` cover: secure defaults, every variable validation via
  `expect_failures`, policy composition through the root inputs, override
  exclusivity, the spec/usage matrix, rotation rules, aliases, grants, the
  data-source fallback, and every advisory check.
- `tests/multi_region_example.tftest.hcl` applies `examples/multi-region` against
  mock providers and requires the primary's and the replica's policies to be
  identical.
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

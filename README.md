# aws.modules.ksm (AWS KMS)

Provisions one customer-managed AWS KMS key per module call together with what a key cannot be used without: a composed key policy, aliases, and grants. A `replica` submodule creates a multi-Region replica of the key in another Region. The module is secure by default and explicit by declaration: rotation is on, the deletion window is the 30-day maximum, the policy always names a principal, and every administrator, user, service principal, extra statement, alias, and grant is a typed, validated input. The policy renderer is a pure submodule you can use on its own, and the whole policy can be replaced by a caller-supplied document without changing the module's outputs. The repository keeps its historical name `ksm`; the module manages KMS. Requires Terraform >= 1.7 and the AWS provider >= 6.35, < 7.

## Why this module

What you get without setting anything beyond `description`:

- A symmetric encryption key (`SYMMETRIC_DEFAULT`, `ENCRYPT_DECRYPT`) with automatic rotation on. Rotation on a spec that cannot rotate (asymmetric, HMAC, or a custom key store) is rejected at plan time, not at apply time.
- A 30-day deletion window, the maximum AWS allows, so an accidental destroy can be cancelled.
- A key policy that grants administration to the account root only, rendered from typed inputs rather than a hand-written JSON string, so IAM policies in the account govern the key and every statement you add is validated before it reaches KMS.
- The KMS policy lockout safety check left on: KMS refuses a policy under which the caller could no longer administer the key.
- Plan-time validation of the key spec and usage matrix, rotation support, alias names, grant operations, principal ARNs, service principals, statement Sids, and every identifier, with messages that name the input to change.
- Advisory `check` blocks that warn when root administration is disabled without a named administrator (a locked key) and when a symmetric key does not rotate.
- No data-source reads when you pass `account_id` and `partition`; the lookups run only as a fallback when those are null.

## Quick start

```hcl
module "orders_key" {
  source = "git::https://github.com/hatan4ik/aws.modules.ksm.git?ref=<commit-sha>" # v1.0.0

  description = "Application data key for the orders service"
  aliases     = ["orders/data"]

  account_id = "123456789012"
  partition  = "aws"

  key_administrator_arns = ["arn:aws:iam::123456789012:role/platform/kms-admin"]
  key_user_arns          = ["arn:aws:iam::123456789012:role/orders-task"]

  tags = { Environment = "prod", Owner = "orders" }
}
```

This creates one rotating symmetric key with the `Name` tag `orders/data`, the alias `alias/orders/data`, and a four-statement policy: the account root may do everything, `kms-admin` may administer but not use the key, `orders-task` may encrypt, decrypt, re-encrypt, generate data keys, and describe the key, and may create grants only for AWS resources that integrate with KMS. Reference the key through `module.orders_key.arn` or `module.orders_key.alias_arns["orders/data"]`.

## Architecture

```text
root (one key)
├── modules/key-policy             Pure renderer: typed inputs -> key policy JSON. No resources, no provider.
├── data.aws_caller_identity       Only when account_id is null; pass the input to skip the lookup.
├── data.aws_partition             Only when partition is null.
├── aws_kms_key.this               Spec and usage matrix, rotation, deletion window, multi-Region flag, custom key store.
├── aws_kms_alias.this["<alias>"]  One resource per alias; adding or removing one never touches the others.
└── aws_kms_grant.this["<name>"]   One resource per grant; grant tokens are a sensitive output.

modules/replica (one replica key, provider passed by the caller)
├── modules/key-policy             The same renderer; partition and account parsed from primary_key_arn.
├── aws_kms_replica_key.this
└── aws_kms_alias.this["<alias>"]
```

The root resolves the account and partition (inputs first, lookups as a fallback), hands them with the policy inputs to `key-policy`, and puts the rendered JSON on the key unless `policy_json_override` is set, in which case the renderer is not instantiated at all. Aliases and grants reference the key ID, so they are created after the key and destroyed before it.

| Concern | Managed by default | Bring your own |
| --- | --- | --- |
| Key policy | Composed from `enable_root_administration`, `key_administrator_arns`, `key_user_arns`, `key_service_principals`, and `policy_statements` by `modules/key-policy`. | `policy_json_override` applies your document verbatim; the typed policy inputs must then be empty (a precondition enforces it). Output `policy` is identical either way. |
| Account and partition | Read through `aws_caller_identity` and `aws_partition` when the inputs are null. | Pass `account_id` and `partition`; no lookup runs. |
| Aliases | None until you declare `aliases`. | Declare each name without the `alias/` prefix; `alias_arns` and `alias_names` are keyed by it. |
| Grants | None until you declare `grants`. | One `aws_kms_grant` per entry with validated operations and encryption-context constraints. |
| Replicas | None; the key is single-Region unless `multi_region = true`. | One `modules/replica` call with `providers = { aws = aws.<alias> }` per additional Region. |

## Usage patterns

| Example | What it shows |
| --- | --- |
| [`examples/minimal`](examples/minimal) | The smallest working key: a description and one alias, everything else defaulted, account and partition looked up. |
| [`examples/complete`](examples/complete) | The full policy interface: administrators, users, a CloudWatch Logs service principal limited by encryption context, a cross-account statement limited by `kms:ViaService`, an organization-wide deny, two aliases, a grant, and a custom rotation period. |
| [`examples/multi-region`](examples/multi-region) | A multi-Region primary and a replica in a second Region through `modules/replica` and a provider alias. |
| [`examples/asymmetric-signing`](examples/asymmetric-signing) | An RSA 4096 signing key with rotation declared off, signing actions for its users, and a verifier account. |
| [`examples/multiple-keys`](examples/multiple-keys) | `for_each` over a map of keys: one module call per key sharing administrators and an alias namespace. |

## Security model

Policy

- The composed policy has at most five kinds of statement, in a fixed order: `EnableRootAccess` (`kms:*` to `arn:<partition>:iam::<account>:root`), `AllowKeyAdministration` (the AWS-documented administrator actions, never the use actions), `AllowKeyUse` (only the use actions of the key's `key_usage`), `AllowAttachmentOfPersistentResources` (`kms:CreateGrant`, `kms:ListGrants`, and `kms:RevokeGrant` under `kms:GrantIsForAWSResource = true`, so users can let EBS, RDS, or Lambda attach grants but cannot delegate the key to arbitrary principals), one `AllowServiceUse<Principal>` per service principal under the conditions you declare, and your `policy_statements`. The exact action lists are in [modules/key-policy](modules/key-policy).
- `enable_root_administration = false` removes the root statement. Do it only with `key_administrator_arns` set; the `root_administration_disabled` check warns otherwise, because that is the standard way to lock a key. A policy with no statements at all is rejected before it reaches KMS.
- An `Allow` statement whose principals include `*` must carry a condition. `Deny` statements may name `*` freely, which is how an organization-wide deny is written (see `examples/complete`).
- Every principal ARN must be an IAM or STS principal; every service principal must end in `amazonaws.com` or `amazonaws.com.cn`; statement Sids are alphanumeric and may not collide with the generated ones.
- `bypass_policy_lockout_safety_check` defaults to false.

Key material

- `enable_key_rotation` defaults to true and is allowed only where AWS supports it: `SYMMETRIC_DEFAULT` outside a custom key store. `rotation_period_in_days` (90 to 2560) shortens or lengthens the 365-day default.
- `key_spec` and `key_usage` are validated enums, and a precondition checks the AWS compatibility matrix at plan time: RSA for encryption or signing; ECC for signing and, on NIST curves, key agreement; HMAC for MACs; ML-DSA for signing.
- `deletion_window_in_days` is 7 to 30 and defaults to 30.

Grants

- Operations are validated against the KMS grant operation list, principals must be IAM or STS principals, and constraints must carry at least one encryption-context pair. `grant_tokens` is a sensitive output.

Not created here

- IAM roles and users, log groups, buckets, secrets, or anything encrypted with the key. They have separate lifecycles and owners. The module consumes their principals' ARNs and exposes the key's identifiers for them to reference.

## Lifecycle notes

- `deletion_window_in_days` only matters on destroy: KMS schedules the key for deletion and keeps it recoverable for that many days, during which it can be cancelled with `kms:CancelKeyDeletion`. Aliases and grants are removed immediately.
- `key_spec`, `key_usage`, `multi_region`, and `custom_key_store_id` are immutable. Changing any of them replaces the key, and ciphertext produced with the old key cannot be decrypted with the new one.
- Turning `enable_key_rotation` off on an existing key stops future rotations; past key material stays available for decryption.
- Changing the policy inputs updates the policy in place. Renaming an alias destroys `aws_kms_alias.this["old"]` and creates `["new"]`; the other aliases are untouched.
- A grant's `retire_on_delete` decides whether Terraform retires the grant (cooperative, what service-linked roles expect) or revokes it (immediate, the default) on destroy.
- Two `check` blocks warn on every plan and apply but never block: `root_administration_disabled` and `rotation_disabled_for_symmetric_key`.
- The `Name` tag is the first alias in sorted order, or the description when there is no alias, unless you set `Name` yourself. Caller tags are never overridden.

## Testing

Two layers, deliberately separate:

- **Contract tests** (`tests/`, run by `make test` and by CI) use `mock_provider`: no credentials, nothing created, placeholder identifiers such as the AWS documentation account `123456789012`. They pin the module's interface, validations, rendered policy JSON, and defaults, and run identically for everyone.
- **Integration suite** (`tests/integration/`, run by `make integration-smoke` or the dispatch-only `integration` workflow) applies the module for real in **your** account with **your** credentials and region from the environment, names your own identity as the key's administrator, user, and grantee, and destroys everything afterwards. `smoke` proves that a rotating key with two aliases, a composed policy, and a grant is accepted by the KMS APIs and that the account and partition fallback resolves to your account. The destroyed key stays visible as pending deletion for its 7-day window; see [tests/integration/README.md](tests/integration/README.md) for that, the permissions, and the GitHub environment contract.

## Design principles

- Single responsibility. `modules/key-policy` owns the shape of a key policy and nothing else: no resources, no provider. `modules/replica` owns a replica key and its aliases. The root owns the primary key, its aliases, and its grants, and composes the renderer.
- Open/closed. New access is added by declaring data (an administrator, a user, a service principal with conditions, a statement, an alias, a grant), not by editing the module. The whole policy can be swapped for a caller document through `policy_json_override`.
- Liskov substitution. A caller-supplied policy is a drop-in for the composed one: outputs are identical. A replica exposes the same identifier outputs as the primary.
- Interface segregation. Feature groups are optional and default to empty. A minimal key needs only `description`. Policy, alias, grant, and replica concerns are separate inputs and separate submodules.
- Dependency inversion. The root depends on principal ARNs and account identifiers, never on how they were produced. The replica derives the partition and account from `primary_key_arn` and performs no lookups; the root looks them up only when you do not pass them.

The full rationale, including why the v0.1.x design was replaced, is in [docs/DESIGN.md](docs/DESIGN.md).

## Compatibility and scope

- Terraform `>= 1.7.0, < 2.0.0`. AWS provider `>= 6.35.0, < 7.0.0`.
- Key specs: `SYMMETRIC_DEFAULT`, `RSA_2048/3072/4096`, `ECC_NIST_P256/P384/P521`, `ECC_SECG_P256K1`, `HMAC_224/256/384/512`, `ML_DSA_44/65/87`. CloudHSM custom key stores through `custom_key_store_id` (symmetric, single-Region, no automatic rotation).
- Roadmap: external key stores (`xks_key_id`), the China-only `SM2` spec, and imported key material. They will arrive as optional inputs and will not break the v1 interface.

## Versioning and releases

Releases follow semantic versioning: incompatible interface changes bump the major version, new optional inputs and outputs bump the minor version, fixes bump the patch version. Every release is a signed annotated tag `vX.Y.Z`.

Pin the full commit SHA of the release tag and record the tag in a comment, so the source cannot move under you:

```hcl
module "orders_key" {
  source = "git::https://github.com/hatan4ik/aws.modules.ksm.git?ref=<commit-sha>" # v1.0.0
}

module "orders_key_replica" {
  source = "git::https://github.com/hatan4ik/aws.modules.ksm.git//modules/replica?ref=<commit-sha>" # v1.0.0
}
```

The `module-release` workflow publishes an immutable GitHub release only from a GitHub-verified, signed, annotated semantic-version tag that points at the merged `main` revision; lightweight or unsigned tags are rejected before anything is published. With a GitHub-associated GPG or SSH signing key configured:

```bash
git fetch origin
git tag -s vX.Y.Z <commit> -m "vX.Y.Z"
git push origin vX.Y.Z
gh workflow run module-release.yml --ref vX.Y.Z -f release_tag=vX.Y.Z
```

Dispatch from the tag, never from `main`: the workflow verifies that the tag points at the revision it checked out, and a maintenance release for an older line (for example a 0.1.x fix after 1.0.0 landed on `main`) is cut from that line's commit.

Upgrading from 0.1.x: read [docs/UPGRADE-1.0.md](docs/UPGRADE-1.0.md) for the input mapping, the settings that preserve the existing key and alias, and the ready-to-paste `moved` block. All changes are listed in [CHANGELOG.md](CHANGELOG.md).

## Contributing

Development setup, the local quality gate, the test-first workflow, and the release process are described in [CONTRIBUTING.md](CONTRIBUTING.md). Security reports go through [SECURITY.md](SECURITY.md).

## License

Apache-2.0. See [LICENSE](LICENSE).

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.7.0, < 2.0.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.35.0, < 7.0.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 6.35.0, < 7.0.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_key_policy"></a> [key\_policy](#module\_key\_policy) | ./modules/key-policy | n/a |

## Resources

| Name | Type |
|------|------|
| [aws_kms_alias.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_alias) | resource |
| [aws_kms_grant.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_grant) | resource |
| [aws_kms_key.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_account_id"></a> [account\_id](#input\_account\_id) | Twelve-digit ID of the account that owns the key, used for the root principal of the policy. Null reads it through aws\_caller\_identity; pass it to avoid the lookup. | `string` | `null` | no |
| <a name="input_aliases"></a> [aliases](#input\_aliases) | Alias names without the alias/ prefix (letters, digits, /, \_, -; not starting with aws/). Each becomes aws\_kms\_alias.this[<name>]; the first in sorted order is the key's Name tag. | `set(string)` | `[]` | no |
| <a name="input_bypass_policy_lockout_safety_check"></a> [bypass\_policy\_lockout\_safety\_check](#input\_bypass\_policy\_lockout\_safety\_check) | Skip the KMS check that the caller can still administer the key under the new policy. Leave false; a policy that locks the key out needs AWS Support to recover. | `bool` | `false` | no |
| <a name="input_custom_key_store_id"></a> [custom\_key\_store\_id](#input\_custom\_key\_store\_id) | ID of the CloudHSM custom key store that holds the key material. Requires SYMMETRIC\_DEFAULT, single-Region, and enable\_key\_rotation = false. Immutable. | `string` | `null` | no |
| <a name="input_deletion_window_in_days"></a> [deletion\_window\_in\_days](#input\_deletion\_window\_in\_days) | Days the key stays recoverable after destroy before KMS deletes it (7-30). | `number` | `30` | no |
| <a name="input_description"></a> [description](#input\_description) | Human-readable purpose of the key. Also the Name tag when no alias is declared. | `string` | n/a | yes |
| <a name="input_enable_key_rotation"></a> [enable\_key\_rotation](#input\_enable\_key\_rotation) | Rotate the key material automatically. Supported only for SYMMETRIC\_DEFAULT keys outside custom key stores; set false explicitly for every other key. | `bool` | `true` | no |
| <a name="input_enable_root_administration"></a> [enable\_root\_administration](#input\_enable\_root\_administration) | Render the EnableRootAccess statement that grants kms:* to the account root, which lets IAM policies in the account control the key. Disable it only when key\_administrator\_arns names who can administer the key; the root\_administration\_disabled check warns otherwise. | `bool` | `true` | no |
| <a name="input_grants"></a> [grants](#input\_grants) | Grants keyed by grant name. grantee\_principal receives operations (KMS grant operations such as Decrypt, Encrypt, GenerateDataKey, CreateGrant); constraints limit them to an encryption context; retiring\_principal may retire the grant; retire\_on\_delete retires instead of revoking on destroy. | <pre>map(object({<br/>    grantee_principal  = string<br/>    operations         = set(string)<br/>    retiring_principal = optional(string)<br/>    constraints = optional(object({<br/>      encryption_context_equals = optional(map(string))<br/>      encryption_context_subset = optional(map(string))<br/>    }))<br/>    grant_creation_tokens = optional(set(string))<br/>    retire_on_delete      = optional(bool, false)<br/>  }))</pre> | `{}` | no |
| <a name="input_is_enabled"></a> [is\_enabled](#input\_is\_enabled) | Whether the key is enabled for cryptographic operations. | `bool` | `true` | no |
| <a name="input_key_administrator_arns"></a> [key\_administrator\_arns](#input\_key\_administrator\_arns) | IAM principal ARNs that may administer the key (create, describe, enable, list, put, update, revoke, disable, get, delete, tag, schedule and cancel deletion, rotate on demand, replicate when multi-Region) but not use it. | `set(string)` | `[]` | no |
| <a name="input_key_service_principals"></a> [key\_service\_principals](#input\_key\_service\_principals) | AWS service principals that may use the key, keyed by principal (for example logs.us-east-1.amazonaws.com). actions defaults to the use actions of key\_usage; conditions restrict the grant, for example an ArnLike on kms:EncryptionContext:aws:logs:arn. | <pre>map(object({<br/>    actions = optional(set(string))<br/>    conditions = optional(list(object({<br/>      test     = string<br/>      variable = string<br/>      values   = set(string)<br/>    })), [])<br/>  }))</pre> | `{}` | no |
| <a name="input_key_spec"></a> [key\_spec](#input\_key\_spec) | Key material specification (the provider attribute customer\_master\_key\_spec): SYMMETRIC\_DEFAULT, RSA\_2048/3072/4096, ECC\_NIST\_P256/P384/P521, ECC\_SECG\_P256K1, HMAC\_224/256/384/512, or ML\_DSA\_44/65/87. Must be compatible with key\_usage. Immutable. | `string` | `"SYMMETRIC_DEFAULT"` | no |
| <a name="input_key_usage"></a> [key\_usage](#input\_key\_usage) | Cryptographic usage: ENCRYPT\_DECRYPT, SIGN\_VERIFY, GENERATE\_VERIFY\_MAC, or KEY\_AGREEMENT. Must be compatible with key\_spec (validated at plan time). Immutable. | `string` | `"ENCRYPT_DECRYPT"` | no |
| <a name="input_key_user_arns"></a> [key\_user\_arns](#input\_key\_user\_arns) | IAM principal ARNs that may use the key with the actions of its key\_usage (for ENCRYPT\_DECRYPT: kms:Encrypt, kms:Decrypt, kms:ReEncrypt*, kms:GenerateDataKey*, kms:DescribeKey) and manage grants for AWS resources that integrate with KMS. | `set(string)` | `[]` | no |
| <a name="input_multi_region"></a> [multi\_region](#input\_multi\_region) | Create a multi-Region primary key that modules/replica can replicate into other Regions. Not supported in custom key stores. Immutable. | `bool` | `false` | no |
| <a name="input_partition"></a> [partition](#input\_partition) | AWS partition of the account (aws, aws-cn, aws-us-gov, ...). Null reads it through aws\_partition; pass it to avoid the lookup. | `string` | `null` | no |
| <a name="input_policy_json_override"></a> [policy\_json\_override](#input\_policy\_json\_override) | Complete key policy JSON applied verbatim instead of the composed policy. Exclusive with key\_administrator\_arns, key\_user\_arns, key\_service\_principals, and policy\_statements. | `string` | `null` | no |
| <a name="input_policy_statements"></a> [policy\_statements](#input\_policy\_statements) | Additional key policy statements keyed by Sid (1-100 alphanumerics, not a generated Sid). principals maps AWS, Service, Federated, or CanonicalUser to identifiers; resources defaults to the key itself; an Allow to a wildcard principal must carry a condition. | <pre>map(object({<br/>    effect     = optional(string, "Allow")<br/>    principals = map(set(string))<br/>    actions    = set(string)<br/>    resources  = optional(set(string), ["*"])<br/>    conditions = optional(list(object({<br/>      test     = string<br/>      variable = string<br/>      values   = set(string)<br/>    })), [])<br/>  }))</pre> | `{}` | no |
| <a name="input_rotation_period_in_days"></a> [rotation\_period\_in\_days](#input\_rotation\_period\_in\_days) | Days between automatic rotations (90-2560). Null keeps the AWS default of 365. Requires enable\_key\_rotation. | `number` | `null` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to the key. The module adds a Name tag (first alias, or the description) unless you set one; caller tags are never overridden. Aliases and grants do not support tags. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_account_id"></a> [account\_id](#output\_account\_id) | Account that owns the key: account\_id when declared, otherwise the looked-up caller account. |
| <a name="output_alias_arns"></a> [alias\_arns](#output\_alias\_arns) | Alias ARNs keyed by alias name (without the alias/ prefix). |
| <a name="output_alias_names"></a> [alias\_names](#output\_alias\_names) | Full alias names (alias/<name>) keyed by alias name. |
| <a name="output_arn"></a> [arn](#output\_arn) | ARN of the key. |
| <a name="output_grant_ids"></a> [grant\_ids](#output\_grant\_ids) | Grant IDs keyed by grant name. |
| <a name="output_grant_tokens"></a> [grant\_tokens](#output\_grant\_tokens) | Grant tokens keyed by grant name, for callers that must use a grant before it propagates. |
| <a name="output_key_id"></a> [key\_id](#output\_key\_id) | ID of the key. |
| <a name="output_key_spec"></a> [key\_spec](#output\_key\_spec) | Key material specification of the key. |
| <a name="output_key_usage"></a> [key\_usage](#output\_key\_usage) | Cryptographic usage of the key. |
| <a name="output_multi_region"></a> [multi\_region](#output\_multi\_region) | Whether the key is a multi-Region primary. |
| <a name="output_partition"></a> [partition](#output\_partition) | Partition of the key: partition when declared, otherwise the looked-up partition. |
| <a name="output_policy"></a> [policy](#output\_policy) | Key policy JSON applied to the key, composed or supplied. |
<!-- END_TF_DOCS -->

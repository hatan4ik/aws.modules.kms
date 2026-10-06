# replica

Creates one multi-Region replica of a KMS key in another Region, with its own key policy and aliases. It is a separate module because a replica lives in a different Region and therefore under a different provider configuration, which the caller passes with `providers = { aws = aws.<alias> }`. The root module creates the multi-Region primary; this module replicates it. The partition and account come from `primary_key_arn`, so the module performs no account or partition lookups; it reads `aws_partition` (no API call) only when a `cloudwatch-logs` or `secretsmanager` entry in `service_grants` needs the partition's DNS suffix, and fails the plan if that partition differs from the primary's.

## Usage

```hcl
provider "aws" {
  region = "us-east-1"
}

provider "aws" {
  alias  = "replica"
  region = "eu-west-1"
}

# Declared once and passed to the primary and every replica, so the
# independent key policies cannot drift apart.
locals {
  key_usage              = "ENCRYPT_DECRYPT"
  key_administrator_arns = ["arn:aws:iam::123456789012:role/platform/kms-admin"]
  key_user_arns          = ["arn:aws:iam::123456789012:role/orders-task"]
}

module "primary" {
  source = "git::https://github.com/hatan4ik/aws.modules.kms.git?ref=<commit-sha>" # v1.0.0

  description  = "orders data key"
  key_usage    = local.key_usage
  multi_region = true
  aliases      = ["orders/data"]

  key_administrator_arns = local.key_administrator_arns
  key_user_arns          = local.key_user_arns
}

module "replica" {
  source = "git::https://github.com/hatan4ik/aws.modules.kms.git//modules/replica?ref=<commit-sha>" # v1.0.0

  providers = { aws = aws.replica }

  primary_key_arn = module.primary.arn
  description     = "orders data key (eu-west-1 replica)"
  key_usage       = local.key_usage
  aliases         = ["orders/data"]

  key_administrator_arns = local.key_administrator_arns
  key_user_arns          = local.key_user_arns
}
```

> [!WARNING]
> The replica's key policy is independent of the primary's: KMS does not copy or compare them, and this module cannot see the primary's inputs. A replica whose policy differs from the primary's plans and applies cleanly and fails only when a principal uses the key in the replica's Region, typically during a failover. Declare `key_usage` and every policy input once in `locals` and pass the same values to the primary and to every replica, as above and in [`examples/multi-region`](../../examples/multi-region).

## Behaviour

- One replica per call. The replica shares the primary's key ID (`mrk-...`), key material, spec, and usage, and has its own Region, policy, aliases, tags, enabled state, and deletion window. Replicate into another Region with another call and another provider alias.
- Policy. Composed by `modules/key-policy` from `enable_root_administration`, `key_administrator_arns`, `key_user_arns`, `key_service_principals`, and `policy_statements`, exactly as the root module does, with `multi_region = true` so administrators can replicate. The root principal is `arn:<partition>:iam::<account>:root` with both values parsed from `primary_key_arn`. `key_usage` is required, with no default: it selects the use actions and must equal the primary's usage, which the replica inherits and the module cannot read without a lookup. A wrong value is accepted by KMS and only fails when the replica is used. `policy_json_override` applies a document verbatim and is exclusive with the typed inputs (a precondition on the replica key enforces it).
- Aliases. Alias names are Regional, so a replica needs its own; declare the same names as the primary to address the key identically in both Regions. Each becomes `aws_kms_alias.this["<name>"]`.
- Name tag. The first alias in sorted order, or the description truncated to 256 characters (the AWS tag value limit), unless the caller sets `Name`; caller tags are never overridden.
- Advisory check. `policy_lockout_safety_check_bypassed` warns on every plan and apply while `bypass_policy_lockout_safety_check = true`.
- Validation. `primary_key_arn` must be a multi-Region key ARN (`key/mrk-<32 hex>`); `deletion_window_in_days` is 7 to 30; aliases may not start with `aws/` or carry the `alias/` prefix; `policy_json_override` must be JSON with a `Statement` element; principal ARNs are validated as in the root module. `key_service_principals` and `policy_statements` are validated by `modules/key-policy`, the single owner of the policy rules, for the root and the replica alike.
- Lifecycle. Destroying the replica schedules it for deletion in its Region only; the primary and other replicas are unaffected. Deleting a primary requires every replica to be deleted first, or a replica to be promoted with `kms:UpdatePrimaryRegion`.

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
| <a name="module_key_policy"></a> [key\_policy](#module\_key\_policy) | ../key-policy | n/a |

## Resources

| Name | Type |
|------|------|
| [aws_kms_alias.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_alias) | resource |
| [aws_kms_replica_key.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_replica_key) | resource |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_aliases"></a> [aliases](#input\_aliases) | Alias names for the replica without the alias/ prefix (letters, digits, /, \_, -; not starting with aws/). Each becomes aws\_kms\_alias.this[<name>] in the replica Region. | `set(string)` | `[]` | no |
| <a name="input_bypass_policy_lockout_safety_check"></a> [bypass\_policy\_lockout\_safety\_check](#input\_bypass\_policy\_lockout\_safety\_check) | Skip the KMS check that the caller can still administer the key under the new policy. Leave false; a policy that locks the key out needs AWS Support to recover. | `bool` | `false` | no |
| <a name="input_deletion_window_in_days"></a> [deletion\_window\_in\_days](#input\_deletion\_window\_in\_days) | Days the replica stays recoverable after destroy before KMS deletes it (7-30). | `number` | `30` | no |
| <a name="input_description"></a> [description](#input\_description) | Human-readable purpose of the replica key. A replica does not inherit the primary's description. | `string` | n/a | yes |
| <a name="input_enable_root_administration"></a> [enable\_root\_administration](#input\_enable\_root\_administration) | Render the EnableRootAccess statement that grants kms:* to the account root of the primary key's account. Disable it only when key\_administrator\_arns names who can administer the replica. | `bool` | `true` | no |
| <a name="input_enabled"></a> [enabled](#input\_enabled) | Whether the replica is enabled for cryptographic operations. | `bool` | `true` | no |
| <a name="input_key_administrator_arns"></a> [key\_administrator\_arns](#input\_key\_administrator\_arns) | IAM principal ARNs that may administer the replica but not use it. See modules/key-policy for the action list. | `set(string)` | `[]` | no |
| <a name="input_key_service_principals"></a> [key\_service\_principals](#input\_key\_service\_principals) | AWS service principals that may use the replica, keyed by principal, with optional actions and conditions. Same shape as the root module. | <pre>map(object({<br/>    actions = optional(set(string))<br/>    conditions = optional(list(object({<br/>      test     = string<br/>      variable = string<br/>      values   = set(string)<br/>    })), [])<br/>  }))</pre> | `{}` | no |
| <a name="input_key_usage"></a> [key\_usage](#input\_key\_usage) | Cryptographic usage of the primary key: ENCRYPT\_DECRYPT, SIGN\_VERIFY, GENERATE\_VERIFY\_MAC, or KEY\_AGREEMENT. Required, with no default: a replica always inherits the primary's real usage, and this input only selects the use actions the replica policy grants, so a wrong value is accepted by KMS and surfaces only when the replica is used. Pass the primary's value, for example module.primary.key\_usage. | `string` | n/a | yes |
| <a name="input_key_user_arns"></a> [key\_user\_arns](#input\_key\_user\_arns) | IAM principal ARNs that may use the replica with the actions of key\_usage and manage grants for AWS resources. | `set(string)` | `[]` | no |
| <a name="input_policy_json_override"></a> [policy\_json\_override](#input\_policy\_json\_override) | Complete key policy JSON applied verbatim instead of the composed policy. Exclusive with key\_administrator\_arns, key\_user\_arns, key\_service\_principals, policy\_statements, and service\_grants. | `string` | `null` | no |
| <a name="input_policy_statements"></a> [policy\_statements](#input\_policy\_statements) | Additional key policy statements keyed by Sid. Same shape as the root module; see modules/key-policy. | <pre>map(object({<br/>    effect     = optional(string, "Allow")<br/>    principals = map(set(string))<br/>    actions    = set(string)<br/>    resources  = optional(set(string), ["*"])<br/>    conditions = optional(list(object({<br/>      test     = string<br/>      variable = string<br/>      values   = set(string)<br/>    })), [])<br/>  }))</pre> | `{}` | no |
| <a name="input_primary_key_arn"></a> [primary\_key\_arn](#input\_primary\_key\_arn) | ARN of the multi-Region primary key to replicate (key ID starts with mrk-). The module derives the partition and account from it; the only lookup is aws\_partition, when a regional service\_grants preset needs the DNS suffix. | `string` | n/a | yes |
| <a name="input_service_grants"></a> [service\_grants](#input\_service\_grants) | Pre-built statements for the AWS-documented minimum grant of a common KMS integration, keyed by Sid. Same shape as the root module; see modules/key-policy and docs/DESIGN.md (Service grant presets). A cloudwatch-logs or secretsmanager grant takes effect only on the key in its resource\_arn's Region, so pass the primary's service\_grants unchanged to keep the policies identical. | <pre>map(object({<br/>    service        = string<br/>    resource_arn   = string<br/>    principal_arns = optional(set(string))<br/>  }))</pre> | `{}` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to the replica key. The module adds a Name tag (first alias, or the description) unless you set one; caller tags are never overridden. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_account_id"></a> [account\_id](#output\_account\_id) | Account that owns the key, parsed from primary\_key\_arn. |
| <a name="output_alias_arns"></a> [alias\_arns](#output\_alias\_arns) | Alias ARNs keyed by alias name (without the alias/ prefix). |
| <a name="output_alias_names"></a> [alias\_names](#output\_alias\_names) | Full alias names (alias/<name>) keyed by alias name. |
| <a name="output_arn"></a> [arn](#output\_arn) | ARN of the replica key in its Region. |
| <a name="output_key_id"></a> [key\_id](#output\_key\_id) | ID of the replica key (the same mrk- ID as the primary). |
| <a name="output_partition"></a> [partition](#output\_partition) | Partition of the key, parsed from primary\_key\_arn. |
| <a name="output_policy"></a> [policy](#output\_policy) | Key policy JSON applied to the replica, composed or supplied. |
<!-- END_TF_DOCS -->

# Upgrading from 0.1.x to 1.0.0

## What changed and why

Version 0.1.x created one key with an optional single alias and either a raw `key_policy` JSON string or a root-only default, accepted any `key_usage` and `customer_master_key_spec` string, enabled rotation regardless of spec, and always read the partition and account through data sources. Version 1.0.0 keeps one key per call, renders the policy from typed inputs through the pure `key-policy` submodule (a caller document is still accepted through `policy_json_override`), makes aliases a set and grants a typed map, adds a `replica` submodule for multi-Region keys, validates the spec and usage matrix and rotation support at plan time, and accepts `account_id` and `partition` as inputs so the lookups run only as a fallback. The reasons, and the table of 0.1.x behaviours that were replaced, are in [DESIGN.md](DESIGN.md). This guide gets an existing 0.1.x consumer onto 1.0.0 without recreating the key or its alias.

## Input mapping

Root inputs of 0.1.2:

| 0.1.x input | 1.0.0 equivalent |
| --- | --- |
| `description` | `description`, unchanged. Now validated as 1 to 8192 characters and used as the `Name` tag when there is no alias. |
| `alias_name` | `aliases = ["<alias_name>"]`. A set: add more names to attach more aliases. The alias keeps its name; only its state address changes, from `aws_kms_alias.this[0]` to `aws_kms_alias.this["<alias_name>"]` (see State moves). |
| `key_policy` | `policy_json_override` for the same document applied verbatim, or drop it and declare the policy through `enable_root_administration`, `key_administrator_arns`, `key_user_arns`, `key_service_principals`, and `policy_statements`. The two are exclusive. |
| `deletion_window_in_days` | `deletion_window_in_days`, unchanged (7 to 30, default 30). |
| `enable_key_rotation` | `enable_key_rotation`, unchanged default (true). Now rejected at plan time for any spec other than `SYMMETRIC_DEFAULT` and inside a custom key store, where AWS would have rejected it at apply time. Asymmetric and HMAC keys must set it to false explicitly. |
| `multi_region` | `multi_region`, unchanged. Replicas are created with `modules/replica`. |
| `key_usage` | `key_usage`, unchanged default, now validated: `ENCRYPT_DECRYPT`, `SIGN_VERIFY`, `GENERATE_VERIFY_MAC`, or `KEY_AGREEMENT`, and checked against `key_spec`. |
| `customer_master_key_spec` | `key_spec`. Same values, the name AWS uses today. The provider attribute underneath is still `customer_master_key_spec`, so the key is not replaced. |
| `tags` | `tags`, unchanged shape. The module now adds a `Name` tag unless you set one; caller tags are never overridden. |

New optional inputs with no 0.1.x counterpart: `rotation_period_in_days`, `is_enabled`, `bypass_policy_lockout_safety_check`, `custom_key_store_id`, `account_id`, `partition`, `enable_root_administration`, `key_administrator_arns`, `key_user_arns`, `key_service_principals`, `policy_statements`, and `grants`. All default to the 0.1.x behaviour.

Outputs:

| 0.1.x output | 1.0.0 equivalent |
| --- | --- |
| `arn` | `arn`, unchanged. |
| `key_id` | `key_id`, unchanged. |
| `alias_arn` | `alias_arns["<alias_name>"]`. `alias_names["<alias_name>"]` gives the full `alias/<alias_name>` name. |

New outputs: `key_usage`, `key_spec`, `policy`, `alias_names`, `grant_ids`, `grant_tokens` (sensitive), `multi_region`, `account_id`, `partition`.

A complete rewrite for a consumer whose 0.1.2 block was `module "key"` with `alias_name = "orders/data"`:

```hcl
# 0.1.2
module "key" {
  source = "git::https://github.com/hatan4ik/aws.modules.ksm.git?ref=<0.1.2-commit-sha>" # v0.1.2

  description = "Application data key"
  alias_name  = "orders/data"
  tags        = var.tags
}

# 1.0.0
module "key" {
  source = "git::https://github.com/hatan4ik/aws.modules.ksm.git?ref=<commit-sha>" # v1.0.0

  description = "Application data key"
  aliases     = ["orders/data"]
  tags        = var.tags

  # Optional: pass both so the module reads nothing through data sources.
  account_id = var.account_id
  partition  = "aws"
}

moved {
  from = module.key.aws_kms_alias.this[0]
  to   = module.key.aws_kms_alias.this["orders/data"]
}
```

`module.key.alias_arn` becomes `module.key.alias_arns["orders/data"]`.

A consumer that passed `key_policy` can keep its document unchanged through `policy_json_override`, which yields no policy diff at all:

```hcl
module "key" {
  source = "git::https://github.com/hatan4ik/aws.modules.ksm.git?ref=<commit-sha>" # v1.0.0

  description          = "Application data key"
  aliases              = ["orders/data"]
  policy_json_override = data.aws_iam_policy_document.key.json
}
```

or move the statements into the typed inputs so the module validates them and renders the AWS-documented administrator and user statements for you. The usual 0.1.x hand-written policy (root, an administrator role, a user role, a CloudWatch Logs service principal) becomes:

```hcl
module "key" {
  source = "git::https://github.com/hatan4ik/aws.modules.ksm.git?ref=<commit-sha>" # v1.0.0

  description = "Application data key"
  aliases     = ["orders/data"]
  account_id  = var.account_id
  partition   = "aws"

  key_administrator_arns = ["arn:aws:iam::${var.account_id}:role/platform/kms-admin"]
  key_user_arns          = ["arn:aws:iam::${var.account_id}:role/orders-task"]

  key_service_principals = {
    "logs.${var.region}.amazonaws.com" = {
      conditions = [{
        test     = "ArnLike"
        variable = "kms:EncryptionContext:aws:logs:arn"
        values   = ["arn:aws:logs:${var.region}:${var.account_id}:log-group:*"]
      }]
    }
  }
}
```

Compare the rendered `module.key.policy` output with your old document before applying; statement Sids and action lists will differ from a hand-written policy even when the permissions are the same.

## Preserving existing resources

The key and its alias are updated in place. Nothing is replaced when you keep the same `key_usage`, `key_spec` (formerly `customer_master_key_spec`), `multi_region`, and alias name, because the immutable arguments of `aws_kms_key` map one to one and the alias keeps its `alias/<name>`.

What will change even with those inputs, all in place and all expected:

- The default policy document. 0.1.x rendered one statement with Sid `EnableRootUserPermissions` and string-valued `Principal`, `Action`, and `Resource`; 1.0.0 renders the same grant (`kms:*` to the account root) with Sid `EnableRootAccess` and one-element lists. KMS evaluates the two identically, but the JSON differs, so `terraform plan` shows an in-place update of `policy`. A key that passed `key_policy` and now passes the same document through `policy_json_override` sees no policy change.
- A `Name` tag (the alias name, or the description) is added unless you set `Name` in `tags`.
- The data sources leave state and re-enter it under a `count` index (`data.aws_partition.current[0]`, `data.aws_caller_identity.current[0]`) when you do not pass `partition` and `account_id`, or disappear when you do. Data sources are re-read on every plan; no `moved` block is needed and nothing in AWS is touched.

If you add administrators, users, service principals, or statements at the same time, the policy update grows accordingly. Keep those for a second change if you want the upgrade plan to be minimal.

## State moves

Old addresses are those of 0.1.2 under `module.key` with `alias_name = "orders/data"`. New addresses are under the same `module.key`.

| 0.1.2 address | 1.0.0 address |
| --- | --- |
| `module.key.aws_kms_key.this` | `module.key.aws_kms_key.this` (unchanged) |
| `module.key.aws_kms_alias.this[0]` | `module.key.aws_kms_alias.this["orders/data"]` |
| `module.key.data.aws_partition.current` | `module.key.data.aws_partition.current[0]`, or removed when `partition` is passed. Not moved: data sources are re-read. |
| `module.key.data.aws_caller_identity.current` | `module.key.data.aws_caller_identity.current[0]`, or removed when `account_id` is passed. Not moved. |

Ready to paste into your root configuration, once per module block that declared `alias_name`:

```hcl
moved {
  from = module.key.aws_kms_alias.this[0]
  to   = module.key.aws_kms_alias.this["orders/data"]
}
```

Without the `moved` block Terraform would destroy `alias/orders/data` and create it again in the same apply; the alias name would be briefly absent and anything addressing the key by alias would fail in between.

## Procedure

1. Pin the 1.0.0 release: copy the commit SHA of tag `v1.0.0` into `?ref=<commit-sha>` and put the tag in a trailing comment.
2. Rewrite the module block with the tables above: `alias_name` to `aliases`, `customer_master_key_spec` to `key_spec`, `key_policy` to `policy_json_override` or the typed policy inputs. For an asymmetric or HMAC key, add `enable_key_rotation = false`; the plan fails with a message naming the spec until you do.
3. Optionally pass `account_id` and `partition` so the module performs no lookups.
4. Add the `moved` block for the alias.
5. Run `terraform init -upgrade` to fetch the new module source, then `terraform plan`.
6. Verify the plan. `aws_kms_key.this` must show `update in-place` (the policy and the `Name` tag) or no changes, never `must be replaced`. `aws_kms_alias.this["<name>"]` must show no changes after the move. If the key shows a replacement, compare `key_usage`, `key_spec`, and `multi_region` with the 0.1.x values before applying: replacing a key makes existing ciphertext undecryptable.
7. Apply. The policy and tags update in place; nothing encrypted with the key is affected.
8. Remove the `moved` block in a later change once every workspace that used 0.1.x has applied the upgrade.

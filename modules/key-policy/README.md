# key-policy

Renders one KMS key policy document from typed inputs. It creates no resources and declares no provider, so the policy shape has a single owner and is unit-tested with `terraform test` alone. The root module and the `replica` submodule both call it; call it directly to build a policy for a key managed elsewhere, or to inspect what the root module will apply.

## Usage

```hcl
module "key_policy" {
  source = "git::https://github.com/hatan4ik/aws.modules.ksm.git//modules/key-policy?ref=<commit-sha>" # v1.0.0

  partition  = "aws"
  account_id = "123456789012"
  key_usage  = "ENCRYPT_DECRYPT"

  key_administrator_arns = ["arn:aws:iam::123456789012:role/platform/kms-admin"]
  key_user_arns          = ["arn:aws:iam::123456789012:role/orders-task"]

  key_service_principals = {
    "logs.us-east-1.amazonaws.com" = {
      conditions = [{
        test     = "ArnLike"
        variable = "kms:EncryptionContext:aws:logs:arn"
        values   = ["arn:aws:logs:us-east-1:123456789012:log-group:*"]
      }]
    }
  }

  statements = {
    AllowCrossAccountDecrypt = {
      principals = { AWS = ["arn:aws:iam::210987654321:root"] }
      actions    = ["kms:Decrypt", "kms:DescribeKey"]
    }
  }
}

resource "aws_kms_key" "this" {
  description = "orders"
  policy      = module.key_policy.json
}
```

## Behaviour

- Statement order. `EnableRootAccess`, `AllowKeyAdministration`, `AllowKeyUse`, `AllowAttachmentOfPersistentResources`, one `AllowServiceUse<Principal>` per service principal sorted by principal, then `statements` sorted by Sid. A statement renders only when its input is non-empty.
- Root. `enable_root_administration = true` (the default) grants `kms:*` to `arn:<partition>:iam::<account_id>:root`, which is what lets IAM policies in the account control the key. Disable it only when `key_administrator_arns` names an administrator; the output precondition rejects a policy with no statements at all because KMS would reject it and the key would be locked.
- Administrators. The AWS-documented administrator actions: `kms:Create*`, `kms:Describe*`, `kms:Enable*`, `kms:List*`, `kms:Put*`, `kms:Update*`, `kms:Revoke*`, `kms:Disable*`, `kms:Get*`, `kms:Delete*`, `kms:TagResource`, `kms:UntagResource`, `kms:ScheduleKeyDeletion`, `kms:CancelKeyDeletion`, `kms:RotateKeyOnDemand`, plus `kms:ReplicateKey` when `multi_region = true`. Administrators cannot use the key.
- Users. The use actions of `key_usage`: `kms:Encrypt`, `kms:Decrypt`, `kms:ReEncrypt*`, `kms:GenerateDataKey*`, `kms:DescribeKey` for `ENCRYPT_DECRYPT`; `kms:Sign`, `kms:Verify`, `kms:GetPublicKey`, `kms:DescribeKey` for `SIGN_VERIFY`; `kms:GenerateMac`, `kms:VerifyMac`, `kms:DescribeKey` for `GENERATE_VERIFY_MAC`; `kms:DeriveSharedSecret`, `kms:GetPublicKey`, `kms:DescribeKey` for `KEY_AGREEMENT`. Users also get `kms:CreateGrant`, `kms:ListGrants`, and `kms:RevokeGrant` limited by `Bool kms:GrantIsForAWSResource = true`, so AWS services acting on their behalf (EBS, RDS, Lambda) can attach grants but the users cannot delegate the key to arbitrary principals.
- Service principals. Each key is a service principal (`<service>.amazonaws.com` or a regional form). `actions` defaults to the use actions; `conditions` restrict the grant and are grouped by operator. The Sid is `AllowServiceUse` followed by the principal's alphanumeric tokens in title case (`logs.us-east-1.amazonaws.com` becomes `AllowServiceUseLogsUsEast1AmazonawsCom`).
- Declared statements. The map key is the Sid (1 to 100 alphanumerics, not a generated Sid). `effect` defaults to `Allow`; `principals` maps `AWS`, `Service`, `Federated`, or `CanonicalUser` to identifiers; `resources` defaults to `["*"]`, the key itself; `conditions` are unique per operator and variable. An `Allow` whose principals include `*` must carry a condition.
- Determinism. Principals, actions, resources, and condition values are sorted; principal types are sorted; conditions are grouped by operator; a statement without conditions renders no `Condition` block. Single values render as one-element lists, which the AWS provider treats as equivalent to strings, so the same inputs always produce the same JSON and no spurious diffs.
- Validation. `account_id` is twelve digits, `partition` is `aws` or an `aws-<suffix>`, principal ARNs are IAM or STS principals, service principals end in `amazonaws.com` or `amazonaws.com.cn`, and every condition lists at least one value.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.7.0, < 2.0.0 |

## Providers

No providers.

## Modules

No modules.

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_account_id"></a> [account\_id](#input\_account\_id) | Twelve-digit ID of the account that owns the key. Used to build the account root ARN. | `string` | n/a | yes |
| <a name="input_enable_root_administration"></a> [enable\_root\_administration](#input\_enable\_root\_administration) | Render the EnableRootAccess statement that grants kms:* to the account root, which lets IAM policies in the account control the key. Disable it only when key\_administrator\_arns names who can administer the key, otherwise the key is locked. | `bool` | `true` | no |
| <a name="input_key_administrator_arns"></a> [key\_administrator\_arns](#input\_key\_administrator\_arns) | IAM principal ARNs that may administer the key (create, describe, enable, list, put, update, revoke, disable, get, delete, tag, schedule and cancel deletion, rotate on demand) but not use it. | `set(string)` | `[]` | no |
| <a name="input_key_service_principals"></a> [key\_service\_principals](#input\_key\_service\_principals) | AWS service principals that may use the key, keyed by principal (for example logs.us-east-1.amazonaws.com). actions defaults to the use actions of key\_usage; conditions restrict the grant, for example an ArnLike on kms:EncryptionContext:aws:logs:arn. | <pre>map(object({<br/>    actions = optional(set(string))<br/>    conditions = optional(list(object({<br/>      test     = string<br/>      variable = string<br/>      values   = set(string)<br/>    })), [])<br/>  }))</pre> | `{}` | no |
| <a name="input_key_usage"></a> [key\_usage](#input\_key\_usage) | Cryptographic usage of the key the policy is for: ENCRYPT\_DECRYPT, SIGN\_VERIFY, GENERATE\_VERIFY\_MAC, or KEY\_AGREEMENT. Selects the use actions granted to key\_user\_arns and, by default, to key\_service\_principals. | `string` | `"ENCRYPT_DECRYPT"` | no |
| <a name="input_key_user_arns"></a> [key\_user\_arns](#input\_key\_user\_arns) | IAM principal ARNs that may use the key with the actions of its key\_usage, and manage grants for AWS resources that integrate with KMS. | `set(string)` | `[]` | no |
| <a name="input_multi_region"></a> [multi\_region](#input\_multi\_region) | Whether the key is multi-Region. Adds kms:ReplicateKey to the administrator actions so administrators can create replicas. | `bool` | `false` | no |
| <a name="input_partition"></a> [partition](#input\_partition) | AWS partition of the account that owns the key (aws, aws-cn, aws-us-gov, ...). Used to build the account root ARN. | `string` | `"aws"` | no |
| <a name="input_statements"></a> [statements](#input\_statements) | Additional statements keyed by Sid (1-100 alphanumerics, not one of the generated Sids). principals maps a principal type (AWS, Service, Federated, CanonicalUser) to its identifiers; resources defaults to the key itself. An Allow to a wildcard principal must carry a condition. | <pre>map(object({<br/>    effect     = optional(string, "Allow")<br/>    principals = map(set(string))<br/>    actions    = set(string)<br/>    resources  = optional(set(string), ["*"])<br/>    conditions = optional(list(object({<br/>      test     = string<br/>      variable = string<br/>      values   = set(string)<br/>    })), [])<br/>  }))</pre> | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_json"></a> [json](#output\_json) | Rendered key policy document: sorted statements, sorted principals, actions, resources, and condition values, conditions grouped by operator, no empty blocks. |
| <a name="output_statement_count"></a> [statement\_count](#output\_statement\_count) | Number of statements in the rendered policy. |
<!-- END_TF_DOCS -->

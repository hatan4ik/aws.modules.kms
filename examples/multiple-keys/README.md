# Multiple keys

Creates a set of keys from one root module by using `for_each` on the module
block. `aws.modules.ksm` provisions exactly one key per call on purpose: a key
is the unit that gets its own policy, aliases, grants, and deletion schedule,
and a plan error names the one key that caused it. Sets of keys are therefore
expressed in the caller, as a map of key specifications, not as a list inside
the module. Use this shape when one account needs a key per data class or per
service and you want them declared side by side with shared administrators.

Each entry supplies its description, its users, and optionally the service
principals that may use it; the example derives the alias
`<alias_prefix>/<key>` and a `Purpose` tag. Adding a key is adding a map entry;
removing one schedules exactly that key for deletion. Because every key has its
own module instance, you can still `-target` or `moved` a single one.

## Run

Declare the keys in a `terraform.tfvars`:

```hcl
account_id             = "123456789012"
key_administrator_arns = ["arn:aws:iam::123456789012:role/platform/kms-admin"]

keys = {
  orders = {
    description   = "Orders service data"
    key_user_arns = ["arn:aws:iam::123456789012:role/orders-task"]
  }
  logs = {
    description = "CloudWatch log groups"
    key_service_principals = {
      "logs.us-east-1.amazonaws.com" = {
        conditions = [{
          test     = "ArnLike"
          variable = "kms:EncryptionContext:aws:logs:arn"
          values   = ["arn:aws:logs:us-east-1:123456789012:log-group:*"]
        }]
      }
    }
  }
}
```

```sh
terraform init && terraform plan
```

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.7.0, < 2.0.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.35.0, < 7.0.0 |

## Providers

No providers.

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_key"></a> [key](#module\_key) | ../../ | n/a |

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_account_id"></a> [account\_id](#input\_account\_id) | Twelve-digit ID of the account that owns the keys; passed so no lookup runs per key. | `string` | n/a | yes |
| <a name="input_alias_prefix"></a> [alias\_prefix](#input\_alias\_prefix) | Alias namespace every key is filed under (<prefix>/<key>). | `string` | `"platform"` | no |
| <a name="input_key_administrator_arns"></a> [key\_administrator\_arns](#input\_key\_administrator\_arns) | IAM principal ARNs that administer every key. | `set(string)` | n/a | yes |
| <a name="input_keys"></a> [keys](#input\_keys) | Keys to create, keyed by a short purpose that becomes the alias suffix. Each declares its description, its users, and the service principals that may use it. | <pre>map(object({<br/>    description   = string<br/>    key_user_arns = optional(set(string), [])<br/>    key_service_principals = optional(map(object({<br/>      actions = optional(set(string))<br/>      conditions = optional(list(object({<br/>        test     = string<br/>        variable = string<br/>        values   = set(string)<br/>      })), [])<br/>    })), {})<br/>  }))</pre> | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | AWS region every key is created in. | `string` | `"us-east-1"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to every key. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_alias_names"></a> [alias\_names](#output\_alias\_names) | Full alias name of each key, keyed by purpose. |
| <a name="output_key_arns"></a> [key\_arns](#output\_key\_arns) | Key ARNs keyed by purpose. |
| <a name="output_key_ids"></a> [key\_ids](#output\_key\_ids) | Key IDs keyed by purpose. |
<!-- END_TF_DOCS -->

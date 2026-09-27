# Minimal key

The smallest working call of `aws.modules.ksm`: one symmetric encryption key
with a description and one alias. Everything else keeps the module's secure
defaults: automatic rotation, a 30-day deletion window, a policy that grants
administration to the account root only, single-Region, enabled. The account
and partition for the root principal are looked up through the provider because
the example passes neither `account_id` nor `partition`; pass them to skip the
lookups. Start here when you want to see exactly what a key needs before
layering on administrators, users, service principals, grants, or replicas.

## Run

```sh
terraform init
terraform plan
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
| <a name="input_region"></a> [region](#input\_region) | AWS region the key is created in. | `string` | `"us-east-1"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_alias_arn"></a> [alias\_arn](#output\_alias\_arn) | ARN of the orders/data alias. |
| <a name="output_key_arn"></a> [key\_arn](#output\_key\_arn) | ARN of the key. |
| <a name="output_key_id"></a> [key\_id](#output\_key\_id) | ID of the key. |
| <a name="output_policy"></a> [policy](#output\_policy) | Key policy the module composed: the account root statement only. |
<!-- END_TF_DOCS -->

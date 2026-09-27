# Multi-Region key

A multi-Region primary key in one Region and a replica in another, with the same
administrators, users, and alias name on both. The root module creates the
primary with `multi_region = true`; `modules/replica` creates the replica under
a second provider configuration passed with `providers = { aws = aws.replica }`.
Both keys share one key ID and one set of key material, so ciphertext produced
in one Region decrypts in the other, which is what cross-Region disaster
recovery and global tables need.

The replica module parses the partition and account from `primary_key_arn` and
performs no lookups. Administrators of both keys receive `kms:ReplicateKey`
because the keys are multi-Region. Add a Region by adding another provider
alias and another replica module call.

## Run

```sh
terraform init
terraform plan \
  -var 'key_administrator_arns=["arn:aws:iam::123456789012:role/platform/kms-admin"]' \
  -var 'key_user_arns=["arn:aws:iam::123456789012:role/orders-task"]'
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
| <a name="module_primary"></a> [primary](#module\_primary) | ../../ | n/a |
| <a name="module_replica"></a> [replica](#module\_replica) | ../../modules/replica | n/a |

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_key_administrator_arns"></a> [key\_administrator\_arns](#input\_key\_administrator\_arns) | IAM principal ARNs that administer both keys; they also receive kms:ReplicateKey. | `set(string)` | n/a | yes |
| <a name="input_key_user_arns"></a> [key\_user\_arns](#input\_key\_user\_arns) | IAM principal ARNs that encrypt and decrypt with either key. | `set(string)` | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | AWS region of the primary key. | `string` | `"us-east-1"` | no |
| <a name="input_replica_region"></a> [replica\_region](#input\_replica\_region) | AWS region of the replica key. Must differ from region. | `string` | `"us-west-2"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_key_id"></a> [key\_id](#output\_key\_id) | Multi-Region key ID shared by the primary and the replica. |
| <a name="output_primary_alias_arn"></a> [primary\_alias\_arn](#output\_primary\_alias\_arn) | ARN of the orders/data alias in the primary Region. |
| <a name="output_primary_key_arn"></a> [primary\_key\_arn](#output\_primary\_key\_arn) | ARN of the primary key. |
| <a name="output_replica_alias_arn"></a> [replica\_alias\_arn](#output\_replica\_alias\_arn) | ARN of the orders/data alias in the replica Region. |
| <a name="output_replica_key_arn"></a> [replica\_key\_arn](#output\_replica\_key\_arn) | ARN of the replica key in the replica Region. |
<!-- END_TF_DOCS -->

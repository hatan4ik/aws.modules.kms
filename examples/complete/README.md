# Complete key

Every policy, alias, and grant feature of `aws.modules.ksm` in one call: a
symmetric key rotating every 180 days; declared administrators and users; the
CloudWatch Logs service principal limited by an encryption-context condition to
log groups under one prefix; a cross-account statement limited by
`kms:ViaService` to S3; an organization-wide deny; two aliases; and a grant to
the Auto Scaling service-linked role limited to one volume prefix. The account
and partition are passed in, so the module performs no lookups. Use it as a
reference for the shape of each input, then copy the parts you need.

Two details are easy to miss. The deny statement names a wildcard principal,
which the module allows only because it is a `Deny` (an `Allow` to `*` must
carry a condition), and it pairs `aws:PrincipalOrgID` with
`aws:PrincipalIsAWSService = false` so AWS services acting on your behalf are
not caught by it. And the grant retires rather than revokes on destroy, the
cooperative path for a service-linked role.

## Run

The example takes several account-specific inputs, so a `terraform.tfvars` is
easier than `-var` flags:

```hcl
account_id             = "123456789012"
key_administrator_arns = ["arn:aws:iam::123456789012:role/platform/kms-admin"]
key_user_arns          = ["arn:aws:iam::123456789012:role/orders-task"]
log_group_prefix       = "/aws/ecs/"
consumer_account_id    = "210987654321"
organization_id        = "o-abcdefghij"
autoscaling_role_arn   = "arn:aws:iam::123456789012:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling"
volume_id_prefix       = "vol-"
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
| <a name="input_account_id"></a> [account\_id](#input\_account\_id) | Twelve-digit ID of the account that owns the key; used for the root principal and the log-group condition. | `string` | n/a | yes |
| <a name="input_autoscaling_role_arn"></a> [autoscaling\_role\_arn](#input\_autoscaling\_role\_arn) | ARN of the Auto Scaling service-linked role that receives the volume grant. | `string` | n/a | yes |
| <a name="input_consumer_account_id"></a> [consumer\_account\_id](#input\_consumer\_account\_id) | Twelve-digit ID of the account that may decrypt objects through S3. | `string` | n/a | yes |
| <a name="input_key_administrator_arns"></a> [key\_administrator\_arns](#input\_key\_administrator\_arns) | IAM principal ARNs that administer the key but cannot use it. | `set(string)` | n/a | yes |
| <a name="input_key_user_arns"></a> [key\_user\_arns](#input\_key\_user\_arns) | IAM principal ARNs that encrypt and decrypt with the key. | `set(string)` | n/a | yes |
| <a name="input_log_group_prefix"></a> [log\_group\_prefix](#input\_log\_group\_prefix) | CloudWatch log group name prefix the key may encrypt, for example /aws/ecs/. | `string` | n/a | yes |
| <a name="input_organization_id"></a> [organization\_id](#input\_organization\_id) | AWS Organizations ID (o-...) outside of which every use of the key is denied. | `string` | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | AWS region the key is created in. | `string` | `"us-east-1"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to the key. | `map(string)` | <pre>{<br/>  "Environment": "production",<br/>  "Team": "orders"<br/>}</pre> | no |
| <a name="input_volume_id_prefix"></a> [volume\_id\_prefix](#input\_volume\_id\_prefix) | Encryption-context value (aws:ebs:id) the grant is limited to; a volume ID or a prefix such as vol-. | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_account_id"></a> [account\_id](#output\_account\_id) | Account that owns the key, as declared. |
| <a name="output_alias_arns"></a> [alias\_arns](#output\_alias\_arns) | Alias ARNs keyed by alias name. |
| <a name="output_alias_names"></a> [alias\_names](#output\_alias\_names) | Full alias names keyed by alias name. |
| <a name="output_grant_ids"></a> [grant\_ids](#output\_grant\_ids) | Grant IDs keyed by grant name. |
| <a name="output_grant_tokens"></a> [grant\_tokens](#output\_grant\_tokens) | Grant tokens keyed by grant name, for use before the grant propagates. |
| <a name="output_key_arn"></a> [key\_arn](#output\_key\_arn) | ARN of the key. |
| <a name="output_key_id"></a> [key\_id](#output\_key\_id) | ID of the key. |
| <a name="output_policy"></a> [policy](#output\_policy) | Composed key policy: root, administrators, users, grant management, CloudWatch Logs, the consumer statement, and the organization deny. |
<!-- END_TF_DOCS -->

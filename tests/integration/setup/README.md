# Integration fixtures

Disposable prerequisites for the integration suites in the parent directory:
a unique name with a random suffix and the caller's own identity, account,
partition, and Region, resolved at run time. A KMS key needs no fixture
infrastructure, so this module creates nothing in AWS; the suites name the
caller as the key's administrator, user, and grantee and derive every alias
from the unique name, so a run never references a principal or a name it did
not resolve itself. The module is not a deployable pattern and is excluded
from policy scans (see `.checkov.yml` and `trivy.yaml` at the repository root).

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.7.0, < 2.0.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.35.0, < 7.0.0 |
| <a name="requirement_random"></a> [random](#requirement\_random) | >= 3.6.0, < 4.0.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 6.35.0, < 7.0.0 |
| <a name="provider_random"></a> [random](#provider\_random) | >= 3.6.0, < 4.0.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [random_id.suffix](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/id) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Prefix for the unique fixture name; a random suffix is appended so concurrent runs never collide. The name becomes the alias namespace of the key under test. | `string` | `"ksm-it"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to the key under test in addition to the identifying defaults. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_account_id"></a> [account\_id](#output\_account\_id) | Account the caller's credentials belong to, for asserting the module's identity fallback. |
| <a name="output_name"></a> [name](#output\_name) | Unique fixture name, used as the alias namespace of the key under test. |
| <a name="output_partition"></a> [partition](#output\_partition) | Partition the caller's credentials belong to, for asserting the module's identity fallback. |
| <a name="output_principal_arn"></a> [principal\_arn](#output\_principal\_arn) | ARN of the caller's own identity, named as administrator, user, and grantee of the key under test. |
| <a name="output_region"></a> [region](#output\_region) | Region the key is created in, resolved from the caller's credentials. |
| <a name="output_tags"></a> [tags](#output\_tags) | Identifying tags applied to the key under test. |
<!-- END_TF_DOCS -->

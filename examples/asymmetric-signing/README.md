# Asymmetric signing key

An RSA 4096 key with `key_usage = "SIGN_VERIFY"` for signing release
artifacts. Signing pipelines are declared as key users and receive exactly the
signing actions (`kms:Sign`, `kms:Verify`, `kms:GetPublicKey`,
`kms:DescribeKey`), because the module selects use actions by `key_usage`. A
verifier account may fetch the public key and verify signatures through an
extra statement, but cannot sign.

Automatic rotation does not exist for asymmetric key material, so
`enable_key_rotation = false` is declared explicitly; leaving the default
`true` fails at plan time with a message naming the spec. The module validates
the spec and usage combination as well, so `RSA_4096` with
`GENERATE_VERIFY_MAC` or `SYMMETRIC_DEFAULT` with `SIGN_VERIFY` are rejected
before anything reaches AWS.

## Run

```sh
terraform init
terraform plan \
  -var 'signer_role_arns=["arn:aws:iam::123456789012:role/release-pipeline"]' \
  -var verifier_account_id=210987654321
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
| <a name="input_signer_role_arns"></a> [signer\_role\_arns](#input\_signer\_role\_arns) | IAM role ARNs of the release pipelines that sign artifacts. | `set(string)` | n/a | yes |
| <a name="input_verifier_account_id"></a> [verifier\_account\_id](#input\_verifier\_account\_id) | Twelve-digit ID of the account whose principals may verify signatures and fetch the public key. | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_alias_arn"></a> [alias\_arn](#output\_alias\_arn) | ARN of the release/signing alias. |
| <a name="output_key_arn"></a> [key\_arn](#output\_key\_arn) | ARN of the signing key. |
| <a name="output_key_id"></a> [key\_id](#output\_key\_id) | ID of the signing key. |
| <a name="output_key_spec"></a> [key\_spec](#output\_key\_spec) | Key material specification (RSA\_4096). |
| <a name="output_key_usage"></a> [key\_usage](#output\_key\_usage) | Cryptographic usage (SIGN\_VERIFY). |
<!-- END_TF_DOCS -->

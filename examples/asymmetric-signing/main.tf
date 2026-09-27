provider "aws" {
  region = var.region
}

module "key" {
  source = "../../"

  description = "Release artifact signing key"
  aliases     = ["release/signing"]

  key_spec  = "RSA_4096"
  key_usage = "SIGN_VERIFY"

  # AWS does not rotate asymmetric key material; the module rejects rotation
  # on any spec other than SYMMETRIC_DEFAULT, so it must be declared off.
  enable_key_rotation = false

  # Users of a signing key receive kms:Sign, kms:Verify, kms:GetPublicKey,
  # and kms:DescribeKey, not the encryption actions.
  key_user_arns = var.signer_role_arns

  # Anyone in the verifier account may fetch the public key and verify
  # signatures, but not sign.
  policy_statements = {
    AllowVerifierAccountVerify = {
      principals = { AWS = ["arn:aws:iam::${var.verifier_account_id}:root"] }
      actions    = ["kms:Verify", "kms:GetPublicKey", "kms:DescribeKey"]
    }
  }
}

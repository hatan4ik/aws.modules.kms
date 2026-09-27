locals {
  # Inputs win; the data sources exist only for callers that cannot supply
  # them (see main.tf). Conditionals, not ||, so a null input is never
  # dereferenced.
  account_id = var.account_id != null ? var.account_id : data.aws_caller_identity.current[0].account_id
  partition  = var.partition != null ? var.partition : data.aws_partition.current[0].partition

  name   = length(var.aliases) > 0 ? sort(tolist(var.aliases))[0] : var.description
  policy = var.policy_json_override != null ? var.policy_json_override : module.key_policy[0].json

  # AWS compatibility matrix: which key usages each key spec supports.
  key_spec_usages = {
    SYMMETRIC_DEFAULT = ["ENCRYPT_DECRYPT"]
    RSA_2048          = ["ENCRYPT_DECRYPT", "SIGN_VERIFY"]
    RSA_3072          = ["ENCRYPT_DECRYPT", "SIGN_VERIFY"]
    RSA_4096          = ["ENCRYPT_DECRYPT", "SIGN_VERIFY"]
    ECC_NIST_P256     = ["SIGN_VERIFY", "KEY_AGREEMENT"]
    ECC_NIST_P384     = ["SIGN_VERIFY", "KEY_AGREEMENT"]
    ECC_NIST_P521     = ["SIGN_VERIFY", "KEY_AGREEMENT"]
    ECC_SECG_P256K1   = ["SIGN_VERIFY"]
    HMAC_224          = ["GENERATE_VERIFY_MAC"]
    HMAC_256          = ["GENERATE_VERIFY_MAC"]
    HMAC_384          = ["GENERATE_VERIFY_MAC"]
    HMAC_512          = ["GENERATE_VERIFY_MAC"]
    ML_DSA_44         = ["SIGN_VERIFY"]
    ML_DSA_65         = ["SIGN_VERIFY"]
    ML_DSA_87         = ["SIGN_VERIFY"]
  }
  key_spec_usage_compatible = contains(local.key_spec_usages[var.key_spec], var.key_usage)

  # Automatic rotation exists only for symmetric keys in the AWS key store.
  symmetric          = var.key_spec == "SYMMETRIC_DEFAULT"
  rotation_supported = local.symmetric && var.custom_key_store_id == null
}

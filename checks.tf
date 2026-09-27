# Advisory checks: they warn on every plan and apply but never block. Each
# describes a configuration that is valid yet usually unintended.

check "root_administration_disabled" {
  assert {
    condition     = var.policy_json_override != null ? true : (var.enable_root_administration ? true : length(var.key_administrator_arns) > 0)
    error_message = "Root administration is disabled and no key_administrator_arns are declared. Only the principals named in the policy can manage this key; if they lose access the key is locked and only AWS Support can recover it."
  }
}

check "rotation_disabled_for_symmetric_key" {
  assert {
    condition     = var.enable_key_rotation ? true : (var.key_spec != "SYMMETRIC_DEFAULT" || var.custom_key_store_id != null)
    error_message = "Automatic rotation is disabled on a symmetric key that supports it. Enable enable_key_rotation unless a compliance regime requires manual rotation."
  }
}

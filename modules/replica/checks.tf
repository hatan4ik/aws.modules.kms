# Advisory checks: they warn on every plan and apply but never block. Each
# describes a configuration that is valid yet usually unintended.

check "policy_lockout_safety_check_bypassed" {
  assert {
    condition     = !var.bypass_policy_lockout_safety_check
    error_message = "bypass_policy_lockout_safety_check is true: KMS will not verify that the caller can still administer the replica under the new policy. A policy that locks the key out can only be recovered by AWS Support. Set it back to false unless this apply must install a policy that intentionally excludes the caller."
  }
}

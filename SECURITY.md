# Security policy

## Supported versions

| Version | Supported |
| --- | --- |
| 1.x | Yes. Security fixes and functional fixes on the latest minor release. |
| 0.1.x | Security fixes only, until 2026-12-31. Upgrade with [docs/UPGRADE-1.0.md](docs/UPGRADE-1.0.md). |
| Unreleased `main` | Not supported for production use. |

## Reporting a vulnerability

Use GitHub private vulnerability reporting on this repository: open the Security tab and choose "Report a vulnerability". Do not open a public issue, pull request, or discussion for a security problem.

Include the module version or commit SHA, the inputs that reproduce the problem, the resulting plan or rendered key policy, and the impact you see.

## What counts

- A module default that weakens security: rotation off where AWS supports it, a deletion window shorter than the maximum, the policy lockout safety check bypassed, a policy that reaches KMS without a principal, a key enabled or disabled contrary to the input.
- A validation bypass: an input the module claims to reject at plan time (an incompatible spec and usage, rotation on an asymmetric key, an invalid alias, an unknown grant operation, an unconditional `Allow` to `*`) but that reaches the provider.
- Policy over-permission: a rendered statement that grants an action, a principal, or a resource the caller did not declare; administrators receiving use actions; users receiving grant management beyond `kms:GrantIsForAWSResource`; a service principal statement rendered without the conditions the caller declared; a generated Sid that a caller statement can silently override.
- A caller-supplied policy document that the module alters before applying it.
- A grant rendered with operations, a grantee, or constraints other than the declared ones, or a grant token exposed through a non-sensitive output.
- A dependency problem in the release pipeline that could publish unverified code.

Findings in your own inputs (for example a `Deny` statement you declared with a wildcard principal, or a policy document you supplied through `policy_json_override`) or in AWS services themselves are out of scope here; report the latter to AWS.

## Response

We acknowledge a report within 5 business days and keep you informed while we confirm, fix, and release. A fix ships as a patch release of every supported line with a `CHANGELOG.md` entry that credits the reporter unless they ask otherwise. Please give us a reasonable window before disclosing publicly.

## Security design

The module is secure by default: automatic rotation on every symmetric key, a 30-day deletion window, a key policy that always names at least one principal and by default only the account root, the KMS lockout safety check left on, administrators who cannot use the key, users who receive only the use actions their key type supports and grant management only for AWS resources, service principals limited to the conditions the caller declares, validated grant operations with sensitive grant tokens, and plan-time validation of every principal ARN, alias, Sid, spec, and usage. Every claim is enforced by a validation, a precondition, or a `check` block with a `terraform test` case behind it. The full description is in the [Security model](README.md#security-model) section of the README, and the reasoning in [docs/DESIGN.md](docs/DESIGN.md).

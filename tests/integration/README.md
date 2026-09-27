# Integration suites

The suites in this directory apply the module for real in **your** AWS account
and destroy everything afterwards. They complement the contract tests in
`tests/`, which run with `mock_provider`, need no credentials, and use the AWS
documentation placeholder account `123456789012` and fake principal ARNs on
purpose: they prove the module's interface and rendering, not that AWS accepts
it. These suites prove the latter.

Nothing here is tied to an account, region, or landing zone. Credentials and
the region come from the environment; the principals named in the key policy
are the caller's own identity, resolved at run time by [`setup/`](setup/), and
every alias carries a random suffix, so concurrent runs never collide.

| Suite | What it proves | Needs | Typical time |
| --- | --- | --- | --- |
| `smoke.tftest.hcl` | A rotating symmetric key with two aliases, the caller as administrator and user, one grant, and a 7-day deletion window is accepted by the KMS APIs; the account and partition lookup fallback resolves to the caller's account; every output reflects what AWS returned. | credentials, region | about 1 minute |

## What is left behind

KMS cannot delete a key immediately. When the suite destroys the key it is
scheduled for deletion with the shortest window the API allows (7 days), stays
visible in the console and in `kms:ListKeys` as `PendingDeletion` for that
time, and is then removed by AWS. This is KMS behaviour, not a leak: a key
pending deletion is not billed and cannot be used. The aliases and the grant
are removed immediately, and every alias name carries the run's random suffix,
so a re-run never collides with a key that is still pending deletion. If you
ever need one of these keys back, cancel the deletion within the window with
`aws kms cancel-key-deletion --key-id <id>`.

## Run it in your account

```bash
export AWS_PROFILE=<your profile>   # or AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY / AWS_SESSION_TOKEN
export AWS_REGION=<region>
make integration-smoke              # terraform init -test-directory=tests/integration && terraform test -test-directory=tests/integration -filter=tests/integration/smoke.tftest.hcl
```

The credentials need the permissions in
[`iam/integration-permissions-policy.json`](iam/integration-permissions-policy.json)
(replace `<ACCOUNT_ID>`). Alias permissions are scoped to names starting with
`ksm-it-`, which is what the fixture produces; `kms:CreateKey` cannot be scoped
to a resource. The identity you run with is written into the key policy as its
administrator and user, so it must be an IAM user, IAM role, or assumed-role
session, which is what profiles, SSO, and the OIDC workflow all produce.

`terraform init -test-directory=tests/integration` also installs the fixture
module's `random` provider and records it in your local `.terraform.lock.hcl`.
Do not commit that change: the committed lock lists only the module's own
provider, and a plain `terraform init` (what CI runs) prunes the entry again.

`terraform test` runs `tests/` only by default, so these suites never run in
the credential-free quality pipeline. The fixture module is excluded from the
Checkov and Trivy scans (`.checkov.yml`, `trivy.yaml`) because it is
short-lived test infrastructure, not a deployable pattern.

## Run it from GitHub Actions (owner lane)

The `integration` workflow (`.github/workflows/integration.yml`) is dispatch-only
and assumes a role through GitHub OIDC. It reads everything account-specific
from the protected `integration` environment of the repository, so the code
stays universal:

| Environment variable | Meaning |
| --- | --- |
| `AWS_INTEGRATION_ROLE_ARN` | Role the workflow assumes. Trust policy: [`iam/github-oidc-trust-policy.json`](iam/github-oidc-trust-policy.json) with `<OWNER>/<REPO>` set to this repository; permissions: the policy above. |
| `AWS_INTEGRATION_REGION` | Region for the key under test. |

Dispatch with `gh workflow run integration.yml -f suite=smoke`. Protect the
environment with required reviewers so a run cannot be started from a pull
request by anyone with write access.

For this repository's owner the environment is prepared with the sandbox
region; the role ARN is added once the role exists in the sandbox account,
created through the platform's delivery IAM module with the trust policy above
and the subject `repo:hatan4ik/aws.modules.ksm:environment:integration`.

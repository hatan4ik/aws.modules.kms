# Contributing

Thank you for improving `aws.modules.ksm`. This guide covers the toolchain, the local quality gate, how features are tested and where they belong, commit and pull request conventions, and how releases are cut.

## Development setup

The module targets Terraform `>= 1.7.0, < 2.0.0` and is developed against 1.7.5, the version the consuming platform pins. Install the toolchain:

| Tool | Purpose | Install |
| --- | --- | --- |
| [tfenv](https://github.com/tfutils/tfenv) | Pin the Terraform version | `tfenv install 1.7.5 && tfenv use 1.7.5` |
| [tflint](https://github.com/terraform-linters/tflint) | Lint with the Terraform and AWS rulesets configured in `.tflint.hcl` | `brew install tflint && tflint --init` |
| [terraform-docs](https://terraform-docs.io) v0.20.0 | Generate the inputs and outputs tables in every README. Pinned to the version bundled by the CI docs action; newer releases change table formatting and fail the drift check (`make docs` refuses other versions). | Download the v0.20.0 binary from the [releases page](https://github.com/terraform-docs/terraform-docs/releases/tag/v0.20.0) |
| [checkov](https://www.checkov.io) | Static security policy | `pip install checkov` |
| [trivy](https://trivy.dev) | Misconfiguration scanning | `brew install trivy` |
| [pre-commit](https://pre-commit.com) | Run the gate on every commit | `pip install pre-commit && pre-commit install` |

Clone, initialise without a backend, and run the gate once to confirm the setup:

```sh
terraform init -backend=false -input=false
make check
```

## Integration suites

`tests/integration/` holds a credential-driven suite that applies the module for real and destroys everything afterwards. It is never part of `make check` or the quality pipeline. Run it against your own account before a release that touches resource behaviour:

```bash
export AWS_PROFILE=<profile> AWS_REGION=<region>
make integration-smoke   # about 1 minute; the destroyed key stays pending deletion for 7 days
```

Add a suite when a feature's correctness depends on the KMS API rather than on rendering (for example a custom key store or a new grant constraint). Keep fixtures in `tests/integration/setup`, keep every value derived from the environment or the fixtures, and never reference a real account, principal, or key.

## The local gate

`make check` is the default target and the same gate CI runs. It stops at the first failing target and must pass before you open a pull request.

| Target | What it runs |
| --- | --- |
| `make fmt` | `terraform fmt -check -recursive -diff` from the repository root. `make fmt-fix` rewrites the files instead. |
| `make validate` | `make init` (`terraform init -backend=false`) followed by `terraform validate` in the root, every submodule, every example directory, and the integration fixture module. |
| `make lint` | `tflint --init` and then `tflint` in every directory with the root `.tflint.hcl`: documented and typed variables, documented outputs, snake_case naming, no unused declarations, pinned required versions and providers. |
| `make test` | `terraform test` in the root and in each `modules/*` directory. No credentials are needed. |
| `make lock` | Refresh the committed root `.terraform.lock.hcl` with hashes for linux and macOS on amd64 and arm64 after changing the provider constraint. CI runs `terraform init` before the docs drift check, so a lock file missing the Linux hash gets rewritten and fails that check. |
| `make docs` | `terraform-docs -c .terraform-docs.yml` in every directory, regenerating the tables between the `BEGIN_TF_DOCS` and `END_TF_DOCS` markers. Run it after touching any variable or output. |
| `make docs-check` | The same in `--output-check` mode: fails when a README is out of date. This is the variant `make check` and CI run. |
| `make security` | `checkov -d . --framework terraform`, and `trivy config --severity HIGH,CRITICAL` when trivy is on the PATH. A skip needs an inline `checkov:skip=` comment with a reason; the only excluded path is the integration fixture module, justified in `.checkov.yml` and `trivy.yaml`. |
| `make check` | `fmt`, `validate`, `lint`, `test`, `docs-check`, `security`, in that order. |

## Test-first workflow

Every behaviour in this module is pinned by a test before it is implemented. Write the failing `run` block first, then the code, then run `make test`.

- Tests live in `tests/*.tftest.hcl` for the root and `modules/<name>/tests/*.tftest.hcl` for each submodule. Root and replica files start with `mock_provider "aws" {}` and a `variables` block holding a valid baseline; the root mocks give `aws_caller_identity` and `aws_partition` `mock_data` defaults so the rendered policy is fully known. The `key-policy` module declares no provider, so its tests have none.
- Use `command = plan`. Nothing here talks to AWS, so tests run in seconds and in CI without credentials.
- Validations are tested with `expect_failures`. Point it at the object that carries the check: `[var.aliases]` for a variable validation, `[aws_kms_key.this]` for a resource precondition, `[output.json]` for the renderer's output precondition, `[check.root_administration_disabled]` for a `check` block. A run with `expect_failures` passes only if exactly those objects fail; add a positive run alongside so the happy path is covered too.
- Assertions must not depend on unknown values. With a mock provider, computed attributes such as ARNs, key IDs, and grant tokens are unknown at plan time, so assert on arguments you set (`policy`, `name`, `tags`, `operations`) and on outputs derived from them. Assert on the decoded policy (`jsondecode(aws_kms_key.this.policy)`) rather than on the string, so formatting is not part of the contract.
- `||` and `&&` do not short-circuit in Terraform 1.7. Both operands are always evaluated, so `var.x == null || var.x.field > 0` fails when `x` is null. Guard with a conditional instead: `var.x == null ? true : var.x.field > 0`. This applies to validations, preconditions, and test assertions alike.
- Keep assertion `error_message` text a statement of the guaranteed behaviour. It becomes the documentation of the contract when a test fails.

## Where to add a feature

Each submodule owns one concern and has one reason to change. The root only composes.

| Concern | Lives in |
| --- | --- |
| The shape of a key policy statement: a new principal role, a new action list, a new condition form, a change to the generated Sids | `modules/key-policy`: add the variable with validation, render it in `main.tf` in the documented order, add a test. Then expose it in the root and the replica submodule and pass it through. The root must not build policy JSON. |
| Replica key arguments | `modules/replica`. The root does not create replicas. |
| Key arguments (rotation, deletion window, key store, enabled state), aliases, grants | Root `main.tf` and `variables.tf`. |
| Cross-input validation the provider would only reject at apply time (spec and usage compatibility, rotation support, override exclusivity) | Root `lifecycle.precondition` blocks on `aws_kms_key.this`, or `checks.tf` when the situation is valid but usually unintended. |
| Identity resolution | Root `main.tf` and `locals.tf`. The data sources are the one documented exception to the no-data-source rule and run only when the input is null; do not add others. |

Rules that apply everywhere: derive from inputs (the account and partition fallback is the only lookup), every variable has a description, a type, and a validation where a wrong value would otherwise fail at apply time, every output has a description, defaults are the secure choice, rendered JSON is sorted and free of null and empty attributes, and a caller-supplied document stays a drop-in for a composed one.

## Commits

Use [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/). The scope is the submodule or root file the change touches.

```text
feat(key-policy): add a principal role for key readers
fix(replica): parse the account from a GovCloud primary key ARN
docs: describe the grant retirement behaviour
test: cover an HMAC key with a custom rotation period
feat!: require aliases instead of alias_name
```

Append `!` after the type or scope for a breaking change and add a `BREAKING CHANGE:` footer explaining what consumers must do. Breaking changes ship only in a major release with an entry in the upgrade guide.

## Pull request checklist

- [ ] `make check` passes locally.
- [ ] New behaviour has a test; changed validations have both a passing and an `expect_failures` run.
- [ ] Variables and outputs have descriptions; `make docs` regenerated the README tables.
- [ ] A policy change is made in `modules/key-policy` and exposed through both the root and the replica submodule.
- [ ] `CHANGELOG.md` has an entry under `## [Unreleased]` in the right category.
- [ ] Breaking changes carry `!`, a `BREAKING CHANGE:` footer, and an update to `docs/UPGRADE-<major>.md`.
- [ ] Examples still initialise and validate; a new feature worth showing has an example.
- [ ] No new data sources, no hard-coded account, region, or partition, no new defaults that weaken security.

## Release process

Releases are cut by maintainers.

1. Move the `## [Unreleased]` entries in `CHANGELOG.md` under a new `## [X.Y.Z] - YYYY-MM-DD` heading, add its compare link, and merge that change to `main`.
2. Create a signed annotated tag on the merge commit. The signing key must be registered with GitHub so the tag shows as Verified:

   ```sh
   git tag -s vX.Y.Z -m "aws.modules.ksm vX.Y.Z"
   git push origin vX.Y.Z
   ```

3. Dispatch the `module-release` workflow (`.github/workflows/module-release.yml`) from the tag with `release_tag = vX.Y.Z`: `gh workflow run module-release.yml --ref vX.Y.Z -f release_tag=vX.Y.Z`. It verifies that the signed tag points at the checked-out revision, then formatting, validation, tests, and generated docs, and publishes the GitHub release. Never dispatch it from `main`: a maintenance release of an older line is cut from that line's commit.
4. Announce the release with the commit SHA. Consumers pin that SHA, not the tag:

   ```hcl
   source = "git::https://github.com/hatan4ik/aws.modules.ksm.git?ref=<commit-sha>" # vX.Y.Z
   ```

Tags are never moved or deleted once published. A bad release is followed by a new patch release.

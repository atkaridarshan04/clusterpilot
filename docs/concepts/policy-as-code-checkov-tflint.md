# Policy as code: checkov and tflint

`.github/workflows/terraform-lint.yml` runs three distinct
checks on every push/PR touching `terraform/**` - each catches a different
class of problem, which is why all three run rather than just one:

- **`terraform validate`** - internal consistency only: types match,
  references resolve. No opinion on whether the config is a *good idea*.
- **`tflint`** - provider-specific correctness: deprecated arguments,
  unused declared variables, wrong AWS attribute names. Valid HCL that's
  still wrong for the AWS provider specifically.
- **`checkov`** - security and misconfiguration: open security groups,
  unencrypted storage, missing IMDSv2, and similar. Config lives in
  `terraform/.checkov.yaml`.

Run the same checks locally before pushing (see `terraform/README.md`'s
"Local checks" section) - none of the three need AWS credentials.

## Findings also surface in GitHub's Security tab, not just the job log

The `checkov` job runs `checkov -d . --output cli --output sarif
--output-file-path console,checkov-results` - the `cli` output goes to the
job's console log as before, and the same findings are written a second
time as a SARIF file
(`terraform/checkov-results/results_sarif.sarif`). A second step,
`github/codeql-action/upload-sarif@v3`, uploads that file to the repo's
code scanning results (**Security tab -> Code scanning**), so findings
show up as annotated alerts tied to the exact file/line, dismissable and
trackable across commits - not just text scrolling by in a CI log. That
upload step needs the job's `permissions: security-events: write`, and
runs with `if: always()` so a failing checkov run (the expected case when
it finds something) still gets its results uploaded rather than silently
dropped.

Code scanning uploads work automatically on a public repo. On a private
repo, this specific feature needs GitHub Advanced Security enabled for
that repo - without it, the upload step itself will fail even though the
SARIF file was generated correctly.

## Recording an intentional exception vs. a repo-wide policy

A finding checkov raises that's a deliberate design choice for this
project - not a bug to fix - gets recorded as close as possible to the
actual resource, so the reasoning stays attached to what it's about:

- **Resource-specific**: an inline `#checkov:skip=CKV_ID:reason` comment
  directly on that resource. Example: `modules/bastion/main.tf`'s open SSH
  ingress/egress and public IP are the bastion's whole point (it's the
  only way in, by design), so those specific checks are skipped there,
  with the reasoning in the comment - not suppressed globally, so an
  unrelated resource that trips the same check in the future still gets
  flagged.
- **Repo-wide**: `terraform/.checkov.yaml`'s `skip-check` list, reserved
  for checks that don't apply to this repo's conventions at all,
  regardless of which resource trips them. The one entry there,
  `CKV_TF_1` (module source pinning), is skipped repo-wide because this
  project pins module versions by semver constraint
  (`version = "~> X.Y"` in each module block) rather than a git
  commit-hash pin - the standard, supported way to consume Terraform
  Registry modules, so the check's underlying concern doesn't apply to how
  this repo sources modules in the first place.

The distinction matters: a resource-level skip says "this specific
resource is an exception," while a repo-wide skip says "this whole class
of finding doesn't apply here." Defaulting to repo-wide suppression for
convenience would silently blind the same check everywhere else it might
legitimately fire later.

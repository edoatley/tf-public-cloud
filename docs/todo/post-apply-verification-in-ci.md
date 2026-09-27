# Post-apply verification in CI

**Summary:** Make a green apply mean "the module works", not just "Terraform succeeded", by
running each module's example script after apply — plus a one-shot preflight that applies,
verifies and destroys so a new module can be proven before a release tag is cut.

**Branch context:** `main` — deferred during the `gcp/private-service-connect` work (#12–#15).

## Why deferred

The PSC module's first deployment took four release tags. Each failure was real but none was
catchable by the existing checks, and fixing the gap properly is a separate concern from
shipping the module. Deliberately scoped down from "apply on every merge to main", which was
judged over-engineered for a learning repo.

## Context

**Relevant files:**
- `.github/workflows/apply-resource.yml` — `workflow_dispatch` only; `resource_type` + `cloud` +
  `action` (apply/destroy) choice inputs; jobs use `environment: production`
- `.github/actions/terraform-run/action.yml` — init → plan → apply/destroy; the step to hook
  after is "apply" (line ~31)
- `scripts/examples/<module>/<cloud>.sh` — the verification scripts. Coverage is uneven: some
  modules have all three clouds, `private-service-connect` has `gcp.sh` only,
  `containerised-app-prod` has `aws.sh` only, `virtual-machine` has no `gcp.sh`
- `scripts/examples/private-service-connect/gcp.sh` — the model to follow: hard assertions that
  exit non-zero, IAP-dependent checks that skip loudly

**Current state:**
`terraform.yml` runs init/fmt/validate/tflint/trivy on PRs touching `*.tf`. Plan and apply are
manual dispatches. Nothing ever runs a verification script automatically — they are documented
but only ever invoked by hand. So "apply succeeded" is currently the strongest signal CI gives,
and for the PSC module that diverged from "it works" across three consecutive releases.

**Key constraints:**
- The `production` environment's deployment branch policy contains a **tag** pattern
  (`release-*`) only. Branches, `main` included, cannot deploy to it. Any new automated flow
  needs its own environment and service account rather than relaxing this.
- GCS backend prefixes are per-module (`gcp/<module>`), not per-ref. Concurrent runs against one
  module would fight over a single state file.
- The GCP jobs pass only `-var="project=..."`; everything else needs a default or a `TF_VAR_*`.
- Verification scripts need `gcloud`/`aws`/`az` authenticated — already true in these jobs via
  the `cloud-login` composite action.

## What to do

1. Add a `verify` step to `apply-resource.yml` after the `terraform-run` step, guarded on
   `inputs.action == 'apply'` and on the script existing:
   `[ -f "scripts/examples/${{ inputs.resource_type }}/${{ matrix-cloud }}.sh" ]`. Run it and let
   a non-zero exit fail the job. Skip with a clear log line when no script exists — do not pass
   silently.
2. Add `preflight` to the `action` choice list. It should run apply → verify → destroy, with the
   destroy in an `if: always()` step so a failed verify still tears down. Report the verify
   result as the job's outcome, not the destroy's.
3. Decide whether preflight reuses `environment: production` (simplest — it is still a
   tag-triggered manual dispatch) or gets its own `integration` environment. Start with
   production; only split if preflight needs to run from `main`.
4. Backfill the missing scripts so the guard in step 1 is rarely hit — at minimum
   `scripts/examples/virtual-machine/gcp.sh`.
5. Document the new action in `docs/GitHub.md` under the `apply-resource.yml` entry, and note
   the preflight step in each module doc's Deploying section.
6. Replace check 5 in `scripts/examples/private-service-connect/gcp.sh`. It currently inspects
   the guest routing table, which in GCP is a /32 plus one default route — so `ip route get`
   returns the same next hop for every destination and the check would pass identically on
   peered VPCs. Substitute two assertions that do prove unreachability: `curl -m 5
   http://<producer_instance_ip>/` must fail (exit 28), and `gcloud compute routes list` for the
   consumer network must show no `nextHopPeering` and no route covering the producer range. The
   second needs no IAP, so it can move into the hard-assertion set.

## Acceptance criteria

- [ ] `action=apply` on a module with a verification script runs it, and a failing script fails
      the workflow run
- [ ] `action=apply` on a module without one logs that it skipped and still succeeds
- [ ] `action=preflight` leaves no resources behind when the verification script fails
- [ ] A deliberately broken module (e.g. producer firewall set to `consumer_cidr` instead of
      `psc_nat_cidr`) is caught by preflight — this is the regression the work exists to prevent
- [ ] `docs/GitHub.md` describes `preflight` alongside apply and destroy
- [ ] Check 5 no longer passes on a guest routing table alone; a peered-VPC setup would fail it

## Related docs

- [`docs/GitHub.md`](../GitHub.md) — workflow reference; `apply-resource.yml` entry at line ~75
- [`scripts/sample-output/private-service-connect.md`](../../scripts/sample-output/private-service-connect.md)
  — records the four-attempt first deployment and why each failure was invisible to static checks
- [`CLAUDE.md`](../../CLAUDE.md) — Rule 8 (fail loud) is the principle behind the skip-loudly
  requirement in step 1

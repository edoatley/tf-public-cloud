# Backfill the missing verification scripts

**Summary:** `container-registry` has no `scripts/examples/` entry for any cloud, so an apply of
it reports "Not verified" rather than proving anything.

**Branch context:** `main` — left over from the post-apply verification work (#18).

## Why deferred

The CI mechanism that runs these scripts landed first. Writing three scripts that cannot be
exercised without deploying the registries — and claiming they work — is the exact failure this
whole thread has been correcting, so they are better written alongside a real deployment.

## Context

**Relevant files:**
- `.github/actions/verify-module/action.yml` — runs `scripts/examples/<module>/<cloud>.sh` after
  an apply; a missing script is a warning annotation and a **Not verified** step summary, never a pass
- `scripts/examples/private-service-connect/gcp.sh` — the model: hard assertions that exit
  non-zero, optional checks that skip loudly
- `scripts/examples/object-storage/` — the closest analogue for a registry, since both are about
  putting an artefact somewhere and reading it back

**Current state:**
Coverage is otherwise complete. Every module that exists for a cloud has a script for it, except
`container-registry`, which has none for aws, gcp or azure. `containerised-app-prod` (aws only)
and `private-service-connect` (gcp only) are complete for the clouds they exist in.

**Key constraints:**
- Scripts discover resources by name through the cloud CLI, not Terraform state, so they run
  without backend access.
- They run in CI after apply with the cloud already authenticated, and locally by hand.
- Exit non-zero on any hard assertion failure. A check that cannot run should print a labelled
  `SKIP` and leave the exit code alone.

## What to do

1. Write `scripts/examples/container-registry/{aws,gcp,azure}.sh`. A registry is empty on
   creation, so the meaningful assertions are that it exists, that its name matches
   `tf-public-cloud`, that immutability/scanning settings are as the module declares, and that
   `docker login` against it succeeds with the CI identity.
2. If asserting on a pushed image, sequence it after `build-and-push.yml` rather than assuming an
   image is present — `docs/GitHub.md` documents that ordering for `containerised-app`.
3. Prove each one with `action=preflight` against a `release-*` tag before merging.
4. Capture the output into `scripts/sample-output/container-registry.md`.

## Acceptance criteria

- [ ] `action=apply --field resource_type=container-registry` no longer reports "Not verified" for
      any of the three clouds
- [ ] Each script exits non-zero when pointed at a project where the registry does not exist
- [ ] `shellcheck` clean
- [ ] `scripts/sample-output/container-registry.md` contains real captured output

## Related docs

- [`docs/GitHub.md`](../GitHub.md) — the `apply-resource.yml` entry describes verify and preflight
- [`docs/containerised-app.md`](../containerised-app.md) — covers the registry modules and the
  build-and-push ordering

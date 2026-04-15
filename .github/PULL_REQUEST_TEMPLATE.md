## Summary

<!-- What does this PR do? Keep it to 1-3 bullet points. -->

## Motivation

<!-- Why is this change needed? Link to issues if applicable. -->

## Changes

<!-- List the key changes. For large PRs, group by module. -->

## Version bump

<!-- Add ONE of these labels to control the release version: -->
<!-- release:patch — bug fixes, docs, refactors (0.1.0 → 0.1.1) -->
<!-- release:minor — new features (0.1.0 → 0.2.0) -->
<!-- release:major — breaking changes (0.1.0 → 1.0.0) -->
<!-- If no label is set, the bump is inferred from commit messages. -->

## Test plan

- [ ] `make test` passes (all Buttercup specs green)
- [ ] `make lint` passes (no byte-compile warnings, checkdoc clean)
- [ ] E2E tests pass (`eor-test-env/scripts/run-tests.sh --profile=vanilla`)
- [ ] Manual smoke test (describe what you tested, or N/A):

```
<!-- Example: -->
<!-- 1. Registered two instances with eor-register-instance -->
<!-- 2. Followed an eor: link from instance-a to instance-b -->
<!-- 3. Ran eor-node-find and verified both instances appeared -->
```

## PR checklist

- [ ] Conventional commit messages used (`feat:`, `fix:`, `docs:`, `test:`, `refactor:`)
- [ ] `CHANGELOG.org` updated under `* Unreleased`
- [ ] All new public functions have docstrings
- [ ] All new public functions have corresponding tests
- [ ] No new `checkdoc` or byte-compile warnings introduced
- [ ] Version bump label applied (`release:patch`, `release:minor`, or `release:major`)

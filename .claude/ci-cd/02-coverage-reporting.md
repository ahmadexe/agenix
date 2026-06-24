# 02 — Coverage Reporting

## Summary
Doc 01 produces a `coverage/lcov.info` and enforces a floor, but the number is invisible
unless you dig into CI logs/artifacts. This doc makes coverage **visible**: a per-PR summary
comment and/or diff coverage, and a README badge, so reviewers can see at a glance whether a
change is tested and whether new code is covered.

## Severity & impact
**High (process).** Visibility is what keeps coverage from silently rotting and gives
reviewers a fast signal. It also makes the "production-grade" claim demonstrable to outsiders
via a badge.

## Files to create / change
- `.github/workflows/ci.yml` (add a reporting step) **or** a dedicated `coverage.yml`
- `README.md` (add a coverage badge)
- Possibly `codecov.yml` (if using Codecov)

## Options (pick one)

### Option A — Codecov (recommended for public packages)
Rich PR comments, diff coverage, sunburst, a badge, and free for open source.
```yaml
      # add after "Run tests with coverage" in ci.yml
      - name: Upload coverage to Codecov
        uses: codecov/codecov-action@v4
        with:
          files: coverage/lcov.info
          fail_ci_if_error: false      # don't fail the build on uploader hiccups
        env:
          CODECOV_TOKEN: ${{ secrets.CODECOV_TOKEN }}  # required for some setups
```
- For public repos, the token is sometimes optional but increasingly recommended — add
  `CODECOV_TOKEN` as a repo secret to be safe.
- Add `codecov.yml` to tune targets and turn the gate informational vs. blocking:
  ```yaml
  # codecov.yml
  coverage:
    status:
      project:
        default:
          target: 85%          # match the floor
          threshold: 1%        # allow tiny dips
      patch:
        default:
          target: 80%          # new/changed lines must be reasonably covered
  comment:
    layout: "reach, diff, files"
    behavior: default
  ```
- Badge in `README.md`:
  ```markdown
  [![codecov](https://codecov.io/gh/ahmadexe/agenix/branch/main/graph/badge.svg)](https://codecov.io/gh/ahmadexe/agenix)
  ```

### Option B — Coveralls
Similar to Codecov; uses `coverallsapp/github-action`. Fine alternative; pick if you already
use Coveralls elsewhere.

### Option C — Zero-dependency PR comment (no third party)
If you'd rather not send coverage to an external service, post the summary as a PR comment from
within the workflow:
```yaml
      - name: Coverage summary
        run: |
          sudo apt-get update && sudo apt-get install -y lcov
          lcov --summary coverage/lcov.info | tee coverage_summary.txt

      - name: Comment coverage on PR
        if: github.event_name == 'pull_request'
        uses: marocchino/sticky-pull-request-comment@v2
        with:
          header: coverage
          path: coverage_summary.txt
```
- Pros: no external service, no data leaves GitHub. Cons: no diff coverage, no badge from the
  service (you can still self-host a badge via shields.io + an endpoint, but that's more work).

## Recommendation
Use **Option A (Codecov)** for a public package — diff coverage on PRs is the single most
useful signal for keeping new code tested, and the badge backs the "production-grade" claim.
Use Option C if the maintainer prefers no third-party data sharing.

## Patch/diff coverage matters
The **project** floor (doc 01) prevents overall regression, but **patch** coverage (are the
*new* lines tested?) is what actually drives good habits. Whichever option you choose, surface
patch/diff coverage on the PR (Codecov/Coveralls do this natively; Option C does not).

## Step-by-step implementation
1. Choose an option. For Codecov: create the Codecov project, add `CODECOV_TOKEN` secret, add
   the upload step to `ci.yml`, add `codecov.yml`.
2. Add the coverage badge to `README.md` (top, near the pub.dev badge).
3. Open a PR and confirm: coverage uploads, the PR shows a coverage comment / diff coverage,
   and the badge renders on `main`.
4. Decide whether the coverage status is **blocking** or **informational**. Recommended:
   project status blocking (matches the doc-01 floor), patch status informational at first,
   then blocking once the suite is mature.

## Acceptance criteria
- Coverage from each CI run is published and visible on the PR (comment and/or status).
- A coverage badge renders in `README.md`.
- New-code (patch/diff) coverage is visible to reviewers (Options A/B).
- If using a third party, the token is stored as a GitHub secret, never committed.

## Related docs
- [01 — CI workflow](01-github-actions-ci-workflow.md) (produces `lcov.info`)
- [../tests/08-coverage-and-quality-gates.md](../tests/08-coverage-and-quality-gates.md) (floor + honest denominator)
- [04 — repo hygiene](04-repo-hygiene-and-automation.md) (make coverage a required check, optional)

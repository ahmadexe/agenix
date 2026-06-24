# 04 — Repo Hygiene & Automation

## Summary
Beyond CI and publishing, a production-grade repo needs the connective tissue that keeps it
healthy over time: automated dependency updates, a protected default branch that *requires* the
green pipeline, ownership/review rules, and contributor-facing templates. The repo has a
`pull_request_template.md` but none of the rest. This doc fills the gaps.

## Severity & impact
**Medium.** None of this affects the shipped bits directly, but collectively it's what keeps
the project from drifting: dependencies going stale (a real risk given the Firebase v6/v13 and
`google_generative_ai` deps), unverified merges sneaking onto `main`, and inconsistent
contributions.

## Files to create / change
- `.github/dependabot.yml`
- `.github/CODEOWNERS`
- `.github/ISSUE_TEMPLATE/bug_report.yml`
- `.github/ISSUE_TEMPLATE/feature_request.yml`
- `.github/ISSUE_TEMPLATE/config.yml`
- Branch protection (configured in GitHub settings, documented here)
- (optional) `.github/workflows/stale.yml`

## 1. Dependabot — automated dependency updates
Keeps `pub` dependencies and GitHub Actions versions current with minimal effort. Important
here because the package pins several fast-moving Firebase plugins and an LLM SDK.
```yaml
# .github/dependabot.yml
version: 2
updates:
  - package-ecosystem: "pub"
    directory: "/"
    schedule:
      interval: "weekly"
    open-pull-requests-limit: 5
    labels: ["dependencies"]
    # Group minor/patch bumps to reduce PR noise; majors come individually.
    groups:
      pub-minor-patch:
        update-types: ["minor", "patch"]

  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "weekly"
    labels: ["ci"]
```
Dependabot PRs run through CI (doc 01), so a bump that breaks tests is caught automatically.

## 2. Branch protection for `main`
Configure in **Settings → Branches → Branch protection rules** (or via the GitHub API/Terraform
if you prefer config-as-code). Document the intended state here so it's reproducible:
- **Require a pull request before merging** (no direct pushes to `main`).
- **Require status checks to pass before merging** → select the CI job
  (`analyze-and-test` from doc 01). Optionally add the coverage status (doc 02).
- **Require branches to be up to date before merging** (so checks run against the merge result).
- **Require conversation resolution before merging.**
- **Require approvals** (≥ 1; for a solo maintainer this can be relaxed, but keep the status
  checks required).
- **Restrict who can push tags** (or use a tag protection rule for `v*`) so only the maintainer
  triggers a publish (doc 03).
- **Do not allow bypassing the above** (or restrict bypass to the maintainer consciously).

> Tag protection: **Settings → Tags** → add a rule for `v*` so only authorized users can
> create release tags, since tags drive publishing.

## 3. CODEOWNERS
Auto-requests review from the right people and pairs with "require review" branch protection.
```
# .github/CODEOWNERS
*                       @ahmadexe
/lib/src/llm/           @ahmadexe
/lib/src/memory/        @ahmadexe
/.github/               @ahmadexe
```
Adjust as the contributor base grows.

## 4. Issue templates
Structured issues reduce back-and-forth. Use GitHub's form schema.
```yaml
# .github/ISSUE_TEMPLATE/bug_report.yml
name: Bug report
description: Something isn't working as documented
labels: ["bug"]
body:
  - type: textarea
    id: what-happened
    attributes:
      label: What happened?
      description: Include the smallest repro you can.
    validations: { required: true }
  - type: input
    id: agenix-version
    attributes: { label: Agenix version }
    validations: { required: true }
  - type: input
    id: flutter-version
    attributes: { label: Flutter/Dart version (flutter --version) }
    validations: { required: true }
  - type: dropdown
    id: llm
    attributes:
      label: LLM provider
      options: [Gemini, Other/custom]
  - type: textarea
    id: logs
    attributes: { label: Relevant logs / stack trace (typed AgenixException?) }
```
```yaml
# .github/ISSUE_TEMPLATE/feature_request.yml
name: Feature request
description: Suggest an improvement
labels: ["enhancement"]
body:
  - type: textarea
    id: problem
    attributes: { label: Problem / use case }
    validations: { required: true }
  - type: textarea
    id: proposal
    attributes: { label: Proposed solution }
```
```yaml
# .github/ISSUE_TEMPLATE/config.yml
blank_issues_enabled: false
contact_links:
  - name: Questions & discussion
    url: https://github.com/ahmadexe/agenix/discussions
    about: Ask usage questions here, not in issues.
```

## 5. PR template
A `pull_request_template.md` already exists — review it and ensure it includes a checklist that
matches the CI gate, e.g.:
- [ ] `dart format` clean
- [ ] `flutter analyze --fatal-infos` clean
- [ ] `flutter test` green; new code covered
- [ ] CHANGELOG updated if user-facing
- [ ] Public API changes exported from `lib/agenix.dart` and documented

## 6. (Optional) Stale bot
Auto-label/close inactive issues/PRs to keep the queue honest.
```yaml
# .github/workflows/stale.yml
name: Stale
on:
  schedule: [{ cron: "0 3 * * *" }]
jobs:
  stale:
    runs-on: ubuntu-latest
    permissions: { issues: write, pull-requests: write }
    steps:
      - uses: actions/stale@v9
        with:
          days-before-stale: 45
          days-before-close: 14
          stale-issue-label: stale
          exempt-issue-labels: "pinned,security"
```

## Step-by-step implementation
1. Add `.github/dependabot.yml` (pub + github-actions).
2. Add `.github/CODEOWNERS`.
3. Add the three `ISSUE_TEMPLATE` files.
4. Review/upgrade `pull_request_template.md` to mirror the CI gate checklist.
5. Configure branch protection on `main` and tag protection on `v*`; document the chosen
   settings in this file (or in a `CONTRIBUTING.md` section).
6. (Optional) Add `stale.yml`.
7. Verify: open a test PR (status checks required, review requested via CODEOWNERS); confirm a
   Dependabot PR appears on schedule and runs CI; confirm direct pushes to `main` are blocked.

## Acceptance criteria
- Dependabot opens PRs for pub + actions updates, which run through CI automatically.
- `main` cannot be pushed to directly; merges require the CI status check (and review per the
  chosen policy).
- Release tags (`v*`) are restricted to authorized users.
- CODEOWNERS requests the right reviewer; issue/PR templates are in place and used.

## Related docs
- [01 — CI workflow](01-github-actions-ci-workflow.md) (the required status check)
- [02 — coverage reporting](02-coverage-reporting.md) (optional required coverage check)
- [03 — release and publish](03-release-and-publish.md) (tag protection guards publishing)

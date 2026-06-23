# Agenix — CI/CD Pipeline Implementation Plan

This folder is a **work backlog** for giving Agenix a real CI/CD pipeline. Today there is no
automation: no workflow runs `flutter analyze`/`flutter test` on a PR, no coverage gate, no
formatting check, no automated publishing to pub.dev, and no dependency/security hygiene. For
a published package, "it passed on my machine" is not a release process — every merge and
every release must be gated and reproducible.

The repo already has `.github/pull_request_template.md`. This backlog adds the workflows and
repo configuration around it.

Every document is written so that **an LLM (or a human) can implement it end-to-end without
re-deriving the analysis**. Each file follows the same structure:

1. **Summary** — what's missing and why it matters.
2. **Severity & impact** — what breaks without it.
3. **Files to create / change** — exact paths.
4. **Current state** — what exists today.
5. **Target design** — the workflow/config, with full YAML.
6. **Step-by-step implementation** — ordered, concrete edits.
7. **Acceptance criteria** — how to know it's done.
8. **Related docs** — cross-links.

> The YAML here is complete and copy-pasteable, but action versions and Flutter versions move.
> Pin to a known-good version and bump deliberately. Re-check each `uses:` ref before relying
> on it.

---

## Prerequisites & assumptions

- This is a **Flutter package** (depends on the Flutter SDK), so CI must install Flutter, not
  just Dart. Use `subosito/flutter-action` (or the official setup) — **not** `dart-lang/setup-dart`
  alone — because `flutter pub get`/`flutter test`/`flutter analyze` are required (see
  `.claude/CLAUDE.md`).
- The package targets Dart `^3.7.2`. Pick a Flutter version whose bundled Dart satisfies that
  (Flutter ≥ 3.29 ships Dart 3.7+). Pin it.
- The test suite (`../tests/`) must be runnable **offline** — no live LLM, no live Firebase.
  CI provides no API keys; tests rely on fakes. If any test needs a secret, it's misdesigned.
- Publishing to pub.dev uses pub.dev's **GitHub Actions automated publishing** (OIDC, no
  long-lived token) — see doc 03.

---

## How to work through this backlog

| #  | Doc | Priority | Theme |
|----|-----|----------|-------|
| 01 | [github-actions-ci-workflow.md](01-github-actions-ci-workflow.md) | Critical | PR gate: format + analyze + test + coverage floor |
| 02 | [coverage-reporting.md](02-coverage-reporting.md) | High | Upload/visualize coverage; PR comment; badge |
| 03 | [release-and-publish.md](03-release-and-publish.md) | High | Tag-driven automated pub.dev publish; pana/score check |
| 04 | [repo-hygiene-and-automation.md](04-repo-hygiene-and-automation.md) | Med | Dependabot, branch protection, CODEOWNERS, templates, stale |

**Suggested sequencing:** 01 → 02 → 03 → 04. CI gate first (it's what protects every other
change in every other backlog), then coverage visibility, then release automation, then
hygiene.

## Definition of done for the whole backlog

- Every PR automatically runs format check + `flutter analyze` + `flutter test --coverage`,
  and fails if any step fails or coverage drops below the floor (`../tests/08`).
- Coverage is visible on each PR (comment and/or badge).
- A version tag (e.g. `v5.0.0`) triggers a verified, automated publish to pub.dev with no
  manual token handling, gated on a clean `dart pub publish --dry-run` and an acceptable
  `pana` score.
- Dependencies are kept current automatically; the default branch is protected so nothing
  merges without a green pipeline.

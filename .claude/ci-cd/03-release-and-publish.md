# 03 — Release & Automated Publishing to pub.dev

## Summary
Publishing is currently manual (someone runs `flutter pub publish` from a laptop), which is
error-prone, unauditable, and risks publishing un-tested or mis-tagged code. This doc sets up
**tag-driven automated publishing** to pub.dev using GitHub Actions' OIDC integration (no
long-lived credentials), gated on the full test suite, a clean `dart pub publish --dry-run`,
and an acceptable `pana` score. It also nails down the version/CHANGELOG discipline for the
v5.0.0 release.

## Severity & impact
**High.** A bad publish is hard to undo (pub.dev versions are immutable; you can only retract).
Automating it behind the green pipeline makes releases safe, repeatable, and traceable to a
specific commit/tag.

## Files to create / change
- `.github/workflows/publish.yml`
- `CHANGELOG.md` (add the `5.0.0` entry — see "Versioning" below)
- `pubspec.yaml` (bump `version:` to match the tag at release time)

## Background: pub.dev automated publishing (OIDC)
pub.dev supports publishing from GitHub Actions **without** storing a credential, via OIDC
token exchange. You configure the package on pub.dev to **trust** this repo's tag-triggered
workflow; the official `dart-lang/setup-dart/.github/workflows/publish.yml` reusable workflow
(or the `dart pub publish` step with the OIDC environment) handles the handshake.

One-time setup on pub.dev:
1. Go to the package's **Admin** tab → **Automated publishing**.
2. Enable **GitHub Actions**, set repository to `ahmadexe/agenix`.
3. Set the **tag pattern** to `v{{version}}` (e.g. `v5.0.0`). pub.dev will only accept a
   publish whose `pubspec.yaml` version matches the tag.

## Target design

### Recommended: the official reusable workflow
```yaml
# .github/workflows/publish.yml
name: Publish to pub.dev

on:
  push:
    tags:
      - 'v[0-9]+.[0-9]+.[0-9]+'   # vMAJOR.MINOR.PATCH

jobs:
  publish:
    permissions:
      id-token: write             # REQUIRED for OIDC token exchange with pub.dev
    uses: dart-lang/setup-dart/.github/workflows/publish.yml@v1
    # The reusable workflow runs `dart pub publish` with OIDC. It assumes a Dart
    # package; for a Flutter package see the custom job below if it can't resolve
    # the Flutter SDK.
```
> **Flutter caveat:** the reusable workflow uses the Dart SDK. Agenix depends on the Flutter
> SDK, so `dart pub get`/`dart pub publish` may fail to resolve the `flutter` dependency. If
> that happens, use the **custom job** below, which installs Flutter and still uses OIDC.

### Custom job (Flutter-aware, OIDC, fully gated)
```yaml
# .github/workflows/publish.yml
name: Publish to pub.dev

on:
  push:
    tags:
      - 'v[0-9]+.[0-9]+.[0-9]+'

jobs:
  guard:
    # Re-run the full CI gate before publishing — never publish unverified code.
    uses: ./.github/workflows/ci.yml

  publish:
    needs: guard
    runs-on: ubuntu-latest
    permissions:
      id-token: write             # OIDC
    steps:
      - uses: actions/checkout@v4

      - uses: subosito/flutter-action@v2
        with:
          channel: stable
          flutter-version: 3.29.0
          cache: true

      - run: flutter pub get

      - name: Verify tag matches pubspec version
        run: |
          TAG="${GITHUB_REF_NAME#v}"
          PUB=$(grep '^version:' pubspec.yaml | awk '{print $2}')
          echo "tag=$TAG pubspec=$PUB"
          test "$TAG" = "$PUB" || { echo "::error::Tag v$TAG != pubspec $PUB"; exit 1; }

      - name: Publish dry-run
        run: dart pub publish --dry-run

      - name: Authenticate to pub.dev via OIDC
        # Exchanges the GitHub OIDC token for a short-lived pub.dev credential.
        run: |
          dart pub token add https://pub.dev \
            --env-var PUB_TOKEN
        env:
          PUB_TOKEN: ${{ secrets.PUB_OIDC_PLACEHOLDER }}  # see note

      - name: Publish
        run: dart pub publish --force
```
> **OIDC mechanics note:** the cleanest path is the official reusable workflow because it wires
> the OIDC exchange for you. If you must hand-roll (custom job), use the
> `dart-lang/setup-dart` action's built-in OIDC support rather than a placeholder token —
> consult the current pub.dev "Automated publishing" docs for the exact step, as the API has
> evolved. **Do not** fall back to a committed/long-lived `credentials.json`. If OIDC truly
> can't be used, store a pub.dev refresh token as an encrypted secret and document the
> rotation policy — but treat that as a last resort.

### Pre-publish quality: `pana`
pub.dev scores packages with `pana`. Run it in CI (informationally first, then as a soft gate)
so the score doesn't regress:
```yaml
      - name: Score with pana
        run: |
          dart pub global activate pana
          dart pub global run pana --no-warning --exit-code-threshold 20 .
```
`--exit-code-threshold` fails if more than N points are lost; start lenient, tighten over time.
Common point losses to fix before release: missing example, missing dartdoc on public API
(the project already enforces `public_member_api_docs`), outdated dependencies, and platform
declarations.

## Versioning & CHANGELOG discipline (v5.0.0)
The hardening + this backlog constitute a **breaking** release. Before tagging `v5.0.0`:
1. Bump `pubspec.yaml` `version: 5.0.0`.
2. Add a `## 5.0.0` entry to `CHANGELOG.md` at the top, documenting **breaking changes** and
   migration notes. At minimum (from the hardening work):
   - `Tool.parameters` is now `List<ParameterSpecification>` (non-nullable, default `const []`).
   - `DataStore.getConversations` no longer takes a `conversationId` argument.
   - `ToolResponse.needsFurtherReasoning` is now `final` and is serialized.
   - New typed exception hierarchy (`AgenixException` and subtypes); `FailureMode` controls
     surfacing.
   - `AgentScope` + `RegistrationPolicy` replace the hidden global registry; `Agent.create`
     gains `scope`, `registrationPolicy`, `failureMode`, `onError`.
   - `DataStore.inMemory()` added; Firebase services are injectable.
   - Plus whatever lands from `../llm-coverage/` (LlmConfig, timeout, retry, streaming, etc.).
3. Follow semver going forward: breaking → major, additive → minor, fixes → patch. The
   tag pattern enforces `vX.Y.Z`.
4. Tag only from `main` after CI is green: `git tag v5.0.0 && git push origin v5.0.0`.

> Per the maintainer's direction, the CHANGELOG/version bump is finalized **once v5 is judged
> truly industry-grade** — i.e., after `../tests/` and `../llm-coverage/` are implemented.
> This doc is the checklist for that moment; don't tag before then.

## Step-by-step implementation
1. Configure automated publishing on pub.dev (Admin → Automated publishing, repo + tag
   pattern `v{{version}}`).
2. Add `.github/workflows/publish.yml` (prefer the official reusable workflow; use the custom
   Flutter-aware job if resolution fails). Ensure `permissions: id-token: write`.
3. Add the tag-vs-pubspec version check and the `dart pub publish --dry-run` gate.
4. Add `pana` scoring (informational first).
5. When ready for v5.0.0: bump `pubspec.yaml`, write the `## 5.0.0` CHANGELOG entry, merge,
   then push the `v5.0.0` tag and watch the publish workflow.
6. Verify the package appears on pub.dev with the correct version and a healthy score.

## Acceptance criteria
- Pushing a `vX.Y.Z` tag triggers a workflow that re-runs the full CI gate, verifies the tag
  matches `pubspec.yaml`, runs a publish dry-run, and publishes via OIDC (no long-lived token
  committed).
- A mismatched tag/version or a failing test/dry-run blocks the publish.
- `pana` runs in CI and its score is tracked.
- The v5.0.0 CHANGELOG entry documents every breaking change with migration notes.

## Related docs
- [01 — CI workflow](01-github-actions-ci-workflow.md) (reused as the publish guard)
- [04 — repo hygiene](04-repo-hygiene-and-automation.md) (protect `main`; restrict who can tag)
- [../tests/README.md](../tests/README.md) and [../llm-coverage/README.md](../llm-coverage/README.md) (must be done before tagging v5)

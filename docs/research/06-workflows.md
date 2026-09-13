# Pen Fight — Build, CI, and Release Workflow Research

Checked 2026-09-12 against live docs/repos where fetchable. `docs.godotengine.org`, `support.google.com`, and `game.ci` were blocked by this session's egress proxy — those claims are sourced from WebSearch summaries of those pages (cached/indexed) rather than a direct fetch, and are flagged **[UNVERIFIED-DIRECT]** below even though they are consistent across multiple independent sources.

---

## 1. Headless Godot export in CI

### Command line invocation (Godot 4)

```bash
# One-time: import all resources so the export doesn't fail on missing .godot cache
godot --headless --editor --quit --import
# Known bug: a single run frequently does not finish importing everything
# (godotengine/godot#77508, #69511, #83449). Run it TWICE, and don't rely on exit code alone:
godot --headless --editor --quit --import || true
godot --headless --editor --quit --import

# Then export
godot --headless --export-release "Android" build/pen-fight.aab
```

- `--export-debug` is the debug-signed equivalent.
- Preset name (`"Android"` above) must match a `[preset.N]` name in `export_presets.cfg` exactly.
- Godot 4 also supports `--export-pack` for PCK-only exports (not relevant to Play).

**The empty-`.godot`-cache trap** (real, current, multiple open upstream issues as of 2026):
- A fresh CI checkout has no `.godot/` import cache (correctly gitignored). The very first headless export attempt fails with errors like `Failed loading resource: res://.godot/imported/icon.svg... Make sure resources have been imported by opening the project in the editor at least once.`
- `godotengine/godot#71521` "Problem exporting in headless mode if the project has never been opened", `#73782` "Headless Export Does Not Import Files", `#77508` "fails to import resources in headless mode if `--quit` or `--quit-after 1` is used (works with `--quit-after 2`)", `#83449` "Exit code 1 after importing in headless mode with `--quit`" — all still open/relevant on Godot 4.x branches.
- **Workaround used by every working CI pipeline found:** run `godot --headless --editor --quit --import` as an explicit pre-step (some projects run it twice, or use `--quit-after 2` instead of `--quit`), and do not treat its exit code as fatal since it is known to sometimes report exit code 1 on a successful import.
- Source: [godotengine/godot#78412 "Cannot export for Android in CI/CD"](https://github.com/godotengine/godot/issues/78412), [#69511](https://github.com/godotengine/godot/issues/69511), [#71521](https://github.com/godotengine/godot/issues/71521), [#73782](https://github.com/godotengine/godot/issues/73782), [#77508](https://github.com/godotengine/godot/issues/77508), [#83449](https://github.com/godotengine/godot/issues/83449).

### `export_presets.cfg` — what's in it, what must not be committed

`export_presets.cfg` lives at the project root and is the source of truth for every export preset (platform, package id, `version/code`, `version/name`, binary format, permissions, and — critically — **keystore paths and passwords**). Example fields from real projects:

```ini
[preset.0]
name="Android"
platform="Android"

[preset.0.options]
package/unique_name="com.yourorg.penfight"
version/code=7
version/name="1.2.0"
gradle_build/use_gradle_build=true
keystore/debug=""
keystore/debug_user=""
keystore/debug_password=""
keystore/release="/Users/dev/keys/pen-fight-release.keystore"
keystore/release_user="pen-fight-key"
keystore/release_password="hunter2"
```

**Secrets that must never be committed:** `keystore/release`, `keystore/release_user`, `keystore/release_password` (and their `keystore/debug*` counterparts if you ever point debug builds at something non-default). Multiple sources confirm Godot writes these plaintext into `export_presets.cfg`, and the official Android docs explicitly warn against distributing/committing it:
> "The `export_presets.cfg` file in your project directory contains your keystore credentials. To keep your credentials secure, do not distribute this file or commit it to a public version control repository." — [Android Developers: Export Godot projects to Android](https://developer.android.com/games/engines/godot/godot-export)

There is an open upstream tracking issue precisely about this design flaw: [godotengine/godot-proposals#1156 "Don't put sensitive credentials such as Android keystore info in export_presets.cfg"](https://github.com/godotengine/godot-proposals/issues/1156) — unresolved as of 2026, which is why the env-var override exists.

### Injecting credentials via environment variables

Godot 4 lets you leave the keystore fields blank/empty in the committed `export_presets.cfg` and supply them at export time via environment variables (added in [godotengine/godot#35930](https://github.com/godotengine/godot/pull/35930)):

- `GODOT_ANDROID_KEYSTORE_DEBUG_PATH`, `GODOT_ANDROID_KEYSTORE_DEBUG_USER`, `GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD`
- `GODOT_ANDROID_KEYSTORE_RELEASE_PATH`, `GODOT_ANDROID_KEYSTORE_RELEASE_USER`, `GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD`

Gotchas confirmed by multiple 2025–2026 forum/issue reports:
- Use an **absolute path**, not `~` or a relative path, for `*_PATH` — tilde is not expanded and relative paths resolve unpredictably ([Godot Forum thread](https://forum.godotengine.org/t/i-need-help-setting-android-environment-variables-for-headless-cli-builds/88717)).
- Set **all three** release variables together — Godot 4 has a known bug where setting only some of the debug/release keystore env vars (not all) causes the release export to fail: [godotengine/godot#109551](https://github.com/godotengine/godot/issues/109551).
- If a JDK isn't findable in the environment, custom-keystore exports fail even with the env vars set correctly: [godotengine/godot#94815](https://github.com/godotengine/godot/issues/94815) — make sure `JAVA_HOME`/`PATH` are set in the CI job (see §2).
- **[UNVERIFIED-DIRECT]** Godot's own docs page (`exporting_for_android.html`) documents these same three-variable pairs; could not fetch it directly this session (proxy-blocked), but the naming is corroborated by the PR that introduced it and by the Android Developers page.

Sources: [PR #35930](https://github.com/godotengine/godot/pull/35930), [godotengine/godot#109551](https://github.com/godotengine/godot/issues/109551), [#94815](https://github.com/godotengine/godot/issues/94815), [Godot Forum](https://forum.godotengine.org/t/i-need-help-setting-android-environment-variables-for-headless-cli-builds/88717).

---

## 2. GitHub Actions pipeline

### Action/image comparison (checked 2026-09-12, via GitHub releases.atom feeds — dates are real, pulled live)

| Option | Latest release | Godot 4 support | Verdict |
|---|---|---|---|
| [`barichello/godot-ci`](https://github.com/abarichello/godot-ci) (Docker image `barichello/godot-ci`) | `4.7.2-stable`, **2026-08-22** | Yes, image tags track Godot versions (`barichello/godot-ci:4.7.2`) | **Actively maintained**, image-per-Godot-version model. Simplest for "just run the CLI in a container." Handles secrets via `SECRET_RELEASE_KEYSTORE_BASE64` / `_USER` / `_PASSWORD` env-var convention baked into its example CI templates. |
| [`firebelley/godot-export`](https://github.com/firebelley/godot-export) (GitHub Action, `uses:` step) | `v8.0.0`, **2026-05-28** (previous major `v7.0.0` was 2025-08-22 — roughly annual major bumps, but present through 2026) | Yes, explicit Godot 4 examples in README | **Maintained but slower cadence.** Reads `export_presets.cfg` itself and runs every preset found; needs `android-actions/setup-android` composed alongside it for Android. Does not itself manage keystore secrets — you inject them yourself. |
| [`chickensoft-games/setup-godot`](https://github.com/chickensoft-games/setup-godot) | `v2.4.2`, **2026-08-28** | Godot 4.x only (3.x explicitly unsupported) | **Actively maintained**, frequent point releases. It's a *setup* action only (installs Godot + optional export templates + caching) — you still write your own export/import steps. Good building block if you want more control than `godot-export` gives you, less turnkey than `godot-ci`. |

All three are currently maintained as of the check date; none show signs of abandonment. `godot-ci`'s per-Godot-version Docker tags make version pinning trivial, which is the deciding factor for a solo dev who wants "tag → build" with minimal glue code — recommended as the primary approach below, with `chickensoft-games/setup-godot` as the fallback if you outgrow the Docker image's assumptions (e.g., need a custom Gradle build for plugins with extra native deps).

### Recommended GitHub Actions workflow

Triggers on any `v*` tag, exports a signed AAB, and attaches it to a GitHub Release.

```yaml
# .github/workflows/release.yml
name: Release Android Build

on:
  push:
    tags:
      - 'v*'

env:
  GODOT_VERSION: "4.7.2-stable"   # pin exactly; match your local editor version

jobs:
  export-android:
    runs-on: ubuntu-latest
    container:
      image: barichello/godot-ci:4.7.2   # matches abarichello/godot-ci release tag above
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0   # need full history + tags for versioning step below

      - name: Set up JDK 17
        uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: '17'

      - name: Set up Android SDK
        uses: android-actions/setup-android@v3

      - name: Cache Godot import + Gradle
        uses: actions/cache@v4
        with:
          path: |
            ~/.local/share/godot/export_templates
            ~/.gradle/caches
            .godot
          key: godot-${{ env.GODOT_VERSION }}-${{ hashFiles('**/*.import', '**/export_presets.cfg') }}
          restore-keys: |
            godot-${{ env.GODOT_VERSION }}-

      - name: Decode release keystore
        env:
          KEYSTORE_BASE64: ${{ secrets.ANDROID_KEYSTORE_BASE64 }}
        run: |
          mkdir -p /root/.android
          echo "$KEYSTORE_BASE64" | base64 -d > /root/.android/release.keystore

      - name: Compute version from tag
        id: version
        run: |
          TAG="${GITHUB_REF_NAME#v}"                 # e.g. v1.4.2 -> 1.4.2
          echo "version_name=$TAG" >> "$GITHUB_OUTPUT"
          # versionCode: monotonic count of tags reachable from HEAD (see §4 for rationale)
          CODE=$(git tag --merged HEAD | wc -l)
          echo "version_code=$CODE" >> "$GITHUB_OUTPUT"

      - name: Patch export_presets.cfg with version + gradle build
        run: |
          sed -i "s/^version\/code=.*/version\/code=${{ steps.version.outputs.version_code }}/" export_presets.cfg
          sed -i "s/^version\/name=.*/version\/name=\"${{ steps.version.outputs.version_name }}\"/" export_presets.cfg

      - name: Import resources (warm-up; run twice, known Godot bug)
        run: |
          godot --headless --editor --quit --import || true
          godot --headless --editor --quit --import

      - name: Export signed release AAB
        env:
          GODOT_ANDROID_KEYSTORE_RELEASE_PATH: /root/.android/release.keystore
          GODOT_ANDROID_KEYSTORE_RELEASE_USER: ${{ secrets.ANDROID_KEYSTORE_ALIAS }}
          GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD: ${{ secrets.ANDROID_KEYSTORE_PASSWORD }}
        run: |
          mkdir -p build
          godot --headless --export-release "Android" build/pen-fight.aab

      - name: Upload artifact
        uses: actions/upload-artifact@v4
        with:
          name: pen-fight-release-aab
          path: build/pen-fight.aab

      - name: Attach AAB to GitHub Release
        uses: softprops/action-gh-release@v2
        with:
          files: build/pen-fight.aab
          generate_release_notes: true
```

Notes:
- `android-actions/setup-android@v3` — official-ish community action for Android SDK/cmdline-tools on GitHub runners; widely used alongside `godot-export`/`godot-ci` pipelines per the `firebelley/godot-export` README's own recommendation.
- `actions/setup-java@v4` with Temurin 17 matches current Android Gradle Plugin/AGP requirements (JDK 17 is the current baseline for modern AGP as of 2026).
- `softprops/action-gh-release` is the de-facto standard maintained action for attaching build artifacts to a GitHub Release on tag push (verify current pin at time of use; not independently re-verified this session — treat the `@v2` tag as **unverified**, check for a newer major before first use).
- Secrets needed in repo settings → Secrets and variables → Actions: `ANDROID_KEYSTORE_BASE64` (output of `base64 -w0 release.keystore`), `ANDROID_KEYSTORE_ALIAS`, `ANDROID_KEYSTORE_PASSWORD` (if key password differs from store password, add a fourth secret and a matching `GODOT_ANDROID_KEYSTORE_RELEASE_*` — Godot 4's Android export currently assumes store and key password are the same field per preset structure above; test this against your actual keystore).

Sources: [barichello/godot-ci](https://github.com/abarichello/godot-ci) (releases.atom confirmed 2026-08-22), [firebelley/godot-export](https://github.com/firebelley/godot-export) (README + releases.atom), [chickensoft-games/setup-godot](https://github.com/chickensoft-games/setup-godot) (releases.atom confirmed 2026-08-28).

---

## 3. GitLab CI equivalent

`abarichello/godot-ci` ships official GitLab CI templates and is the natural fit since the image is the same either way.

```yaml
# .gitlab-ci.yml
image: barichello/godot-ci:4.7.2

stages:
  - export

variables:
  GIT_DEPTH: 0   # need tags for versioning

.export_android_template: &export_android
  stage: export
  rules:
    - if: '$CI_COMMIT_TAG =~ /^v/'   # tag-only job: this stage never runs on branch pushes
  before_script:
    - export ANDROID_KEYSTORE_PATH="$(pwd)/release.keystore"
    - base64 -d "$SECRET_RELEASE_KEYSTORE_BASE64" > "$ANDROID_KEYSTORE_PATH" || cp "$SECRET_RELEASE_KEYSTORE_BASE64" "$ANDROID_KEYSTORE_PATH"
    - VERSION_NAME="${CI_COMMIT_TAG#v}"
    - VERSION_CODE=$(git tag --merged HEAD | wc -l)
    - sed -i "s/^version\/code=.*/version\/code=${VERSION_CODE}/" export_presets.cfg
    - sed -i "s/^version\/name=.*/version\/name=\"${VERSION_NAME}\"/" export_presets.cfg
    - godot --headless --editor --quit --import || true
    - godot --headless --editor --quit --import

export_android:
  <<: *export_android
  script:
    - mkdir -v -p build/android
    - godot --headless --export-release "Android" build/android/pen-fight.aab
  variables:
    GODOT_ANDROID_KEYSTORE_RELEASE_PATH: "$ANDROID_KEYSTORE_PATH"
    GODOT_ANDROID_KEYSTORE_RELEASE_USER: "$SECRET_RELEASE_KEYSTORE_USER"
    GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD: "$SECRET_RELEASE_KEYSTORE_PASSWORD"
  artifacts:
    name: "pen-fight-$CI_COMMIT_TAG"
    paths:
      - build/android/pen-fight.aab
    expire_in: 90 days
```

Meaningful differences from GitHub Actions:
- **Runner image**: identical Docker image (`barichello/godot-ci:<version>`) works natively as GitLab's `image:` — no separate setup-android/setup-java composition needed if using godot-ci's image (it bundles JDK + Android SDK + export templates for that Godot version). If you instead build your own image or use a generic runner, you'd add `apt`/SDK-manager steps GitHub's marketplace actions otherwise hide.
- **CI/CD variables of type "File"**: instead of GitHub's opaque secret strings, GitLab lets you create a project variable with **Type = File**. GitLab writes its *value* to a temp path and exposes that path via the variable name at runtime — so a File-type `SECRET_RELEASE_KEYSTORE_BASE64` variable, when referenced as `$SECRET_RELEASE_KEYSTORE_BASE64` in a script, is already a **path to a file containing the base64 blob**, not the blob itself. That's why the `before_script` above tries both `base64 -d "$VAR"` (path form) with a fallback `cp` — pick the one matching how you actually created the variable, and mark it **Protected** + **Masked** (masking a multi-line/File var has restrictions in GitLab — verify in your instance's UI).
- **`rules:` for tag-only jobs**: `rules: - if: '$CI_COMMIT_TAG =~ /^v/'` is the modern equivalent of the deprecated `only: tags`. Ensures the export/signing job never runs on ordinary branch pipelines (protecting keystore exposure surface).
- **Artifact expiry**: GitLab artifacts expire by default (`expire_in`) unless set to `never`; GitHub Actions artifacts instead follow a repo/org-wide retention-day setting. Set `expire_in: never` or a long window (e.g. `180 days`) if you want the AAB to survive for post-hoc download — GitHub Releases (via `action-gh-release`) don't have this expiry problem since a Release asset is permanent, which is one argument for keeping the "attach to a Release" step even in a GitLab-primary workflow (mirror to GitHub for that, or push a GitLab Release equivalent with `release-cli`).
- **Protected variables & tags**: for real security, mark the branch/tag pattern that can trigger the release job as "Protected" in GitLab (Settings → Repository → Protected tags) and mark the keystore variables "Protected" so they're only injected into pipelines running on protected refs — this has no direct GitHub equivalent beyond environment protection rules.

Source for File-type variables and masking caveats: [GitLab CI/CD Variables & Secrets guide (2026)](https://envmanager.com/blog/gitlab-cicd-secrets); pattern corroborated by multiple Android+GitLab CI walkthroughs found ([Medium: GitLab CI/CD Android signed build](https://rushabhshah065.medium.com/gitlab-ci-cd-create-android-signed-build-upload-build-on-firebase-distribution-dc7824b6ec9a), [tickett.wordpress.com](https://tickett.wordpress.com/2021/08/11/building-android-signed-apks-with-gitlab-ci-cd/)). A working Godot-specific example is at [myood/godot-ci-android-export/.gitlab-ci.yml](https://github.com/myood/godot-ci-android-export/blob/master/.gitlab-ci.yml). **Mark the exact File-variable runtime semantics as [UNVERIFIED] against current GitLab docs** (`docs.gitlab.com` was reachable for one fetch in search results but not independently confirmed this session) — test in a scratch pipeline before relying on it.

---

## 4. Versioning: one source of truth from a git tag

Godot's Android preset stores two numbers in `export_presets.cfg`:
- `version/name` — free-text string shown to users (e.g. `"1.4.2"`).
- `version/code` — an integer Play uses internally for update ordering. Max value `2100000000` ([Android Developers: Version your app](https://developer.android.com/studio/publish/versioning)).

**Play's rule (confirmed):** `versionCode` must be strictly higher than every code your app has *ever* used on Play — across all tracks, including internal-only releases, and even releases you later deleted or unpublished. Play keeps the full history and rejects anything at or below the historical maximum. Source: [Android Developers: Version your app](https://developer.android.com/studio/publish/versioning), corroborated by [Play Console upload-error community docs](https://buddyboss.com/docs/error-uploading-build-to-google-play-store-version-code-2-has-already-been-used/).

### Recommended scheme (survives hotfixes, tag-driven, no manual bookkeeping)

Use **git tags as the single source of truth**, and derive both fields at build time — never hand-edit `export_presets.cfg`'s version fields in a commit:

1. Tag every release `vMAJOR.MINOR.PATCH` (semver), e.g. `v1.4.2`.
2. `version/name` = tag with the `v` stripped: `1.4.2`.
3. `version/code` = a **monotonically increasing integer independent of semver**, because semver can't guarantee strict ordering when a hotfix bumps PATCH past a later MINOR branch's number in Play's terms — Play only cares about a single flat integer. Two safe derivations:
   - **Tag-count approach** (used in the workflow above): `git tag --merged HEAD | wc -l` — increases by exactly 1 for every release tag ever merged into history, including hotfix tags branched off an old commit, as long as hotfix tags are eventually merged back so `--merged HEAD` still counts them. Simple, but merge topology matters — verify with `git tag --merged` semantics for your branching model before trusting it blindly for a hotfix released off an old tag.
   - **Timestamp approach** (more hotfix-proof, doesn't depend on tag/merge topology): `date -u +%s` divided down to fit Play's integer ceiling, or a `YYMMDDNN` scheme like `2609121` (year-month-day + build-of-day counter). Strictly increasing as long as you don't release twice in the same derived unit, and completely decoupled from branch structure — recommended over the tag-count approach for a solo dev doing occasional hotfixes from old tags.
4. Patch `export_presets.cfg` in the CI job right before export (`sed`, shown above) rather than committing the bumped numbers — keeps the file itself branch-agnostic and avoids a "bump version" commit ritual.

**Hotfix scenario worked through:** ship `v1.4.0` (code 40) → `v1.5.0` (code 41) is in progress on `main` → a critical bug is found in `v1.4.0` in production. Branch a hotfix from the `v1.4.0` tag, fix, tag `v1.4.1`. Its versionCode **must still exceed 41** (the highest code ever used), even though `1.4.1` is semantically "older" than the in-flight `1.5.0`. This is why versionCode must be derived from a global monotonic source (build count or timestamp), never from the semver numbers themselves or from "number of commits on this branch."

---

## 5. Signing and keystore hygiene

### Generating a release keystore

```bash
keytool -genkeypair -v \
  -keystore pen-fight-release.keystore \
  -alias pen-fight-upload \
  -keyalg RSA -keysize 2048 \
  -validity 10000
```
You'll be prompted for a keystore password, a key password (can match), and X.500 name fields (name/org/city/country). `-validity 10000` (days, ~27 years) is the standard convention seen across every Android signing guide. Source: [multiple keytool/genkeypair guides](https://gist.github.com/henriquemenezes/70feb8fff20a19a65346e48786bedb8f); command syntax cross-checked, standard `keytool` usage, not Godot-specific.

### Play App Signing: upload key vs. app signing key

Since Play App Signing became mandatory for new apps, there are two distinct keys:
- **Upload key** — yours, used to sign the AAB you upload; Play verifies this signature, strips it, and re-signs with the app signing key before distributing to devices.
- **App signing key** — held by Google, this is what actually establishes your app's identity on user devices and is used for update-compatibility checks and Play integrity/API-key restrictions.

**If the upload key is lost/compromised:** because Google holds the real app signing key, you don't lose the app — go to **Play Console → [App] → Setup → App integrity → Play App Signing → Upload key certificate → Request upload key reset**, pick a reason ("I lost my upload key" / "compromised" / "want to upgrade"), and Google manually reviews the request. Turnaround is reported as anywhere from a few minutes/hours to 1–2 business days. Source: [Play Console Help: Use Play App Signing](https://support.google.com/googleplay/android-developer/answer/9842756?hl=en) (indexed via search, not directly fetched — **[UNVERIFIED-DIRECT]**), corroborated by [community upload-key-reset guide](https://support.google.com/googleplay/android-developer/community-guide/243925915/how-to-request-a-new-upload-key?hl=en).

### Why the keystore must never be in git

- It's the private credential that (for the upload key) authenticates you to Play as the app's owner; anyone with it plus the alias/passwords can sign builds that Play will accept as coming from you until you notice and reset it.
- Godot's own `export_presets.cfg` puts the *plaintext path and passwords* right next to the project — committing that file with real values commits the password even if the `.keystore` binary itself is gitignored. Use the env-var override (§1) or a per-machine `export_credentials.cfg`-style local file kept out of git, per community convention (no official Godot mechanism ships this file name — it's just a pattern some projects use manually).

### Backing it up

No official Godot/Google-specific procedure beyond generic secrets hygiene: keep the `.keystore` file, its passwords, and the alias name together in a password manager or an encrypted offline backup (a cloud secret manager, or 3-2-1 backup of an encrypted archive). Losing the **app signing key** is unrecoverable if you are *not* enrolled in Play App Signing; losing the **upload key** under Play App Signing is recoverable via the reset flow above. There is no case where losing everything is silently fine — treat the keystore as a permanent asset for the app's lifetime.

### Debug keystore

Local debug builds (`--export-debug`) use Android's standard auto-generated debug keystore:
- Path: `~/.android/debug.keystore`
- Password: `android`
- Alias: `androiddebugkey`
- Key password: `android`

These are fixed, publicly known defaults intentionally (debug builds are never meant to be distributed) — source: [multiple Android tooling references, e.g. devops.datenkollektiv.de keystore primer](https://devops.datenkollektiv.de/what-every-android-developer-should-know-about-keystores.html). Do not point CI's release export at the debug keystore, and do not ship a debug-signed build to any Play track.

---

## 6. Play Console release pipeline

### Track comparison (checked 2026-09-12)

| Track | Review | Tester cap | Counts toward production access? |
|---|---|---|---|
| Internal testing | None — live in minutes | Up to **100** testers | No |
| Closed testing | Yes (standard review) | Email lists: up to 2,000 users/list, 50 lists/track, 200 lists total; Google Groups: no stated size limit | **Yes — required** for new personal accounts (see below) |
| Open testing | Yes | Public / unlimited (opt-in join link) | No, but recommended before full production launch |
| Production | Yes | All Play users | — |

Source: [testerscommunity.com 2026 guide](https://www.testerscommunity.com/guides/internal-vs-closed-vs-open-testing-google-play), cross-checked against [primetestlab.com closed-testing stats](https://primetestlab.com/blog/google-play-closed-testing-statistics) and [Play Console Help: Set up an open, closed, or internal test](https://support.google.com/googleplay/android-developer/answer/9845334?hl=en) (indexed, not directly fetched — **[UNVERIFIED-DIRECT]** on exact list-size numbers; treat the 2,000/50/200 figures as reported-not-fetched).

### The 14-day / 12-tester closed testing requirement — verified current status as of 2026-09-12

- **Still in effect.** Applies specifically to **personal Play Console developer accounts created on or after 2023-11-13**. Exempt: organization/business accounts, and personal accounts created before that date.
- Requirement: run closed testing with **at least 12 testers, each continuously opted in for a minimum of 14 days**, before Play grants "Production access." If a tester opts out and back in, the 14-day counter for that tester restarts (must be consecutive).
- **Policy changed recently**: the tester minimum was **reduced from 20 to 12 on 2024-12-11** (duration unchanged at 14 days). Multiple 2026 sources confirm this is the current number, not the original 20.
- This is per-app, not per-account: a new personal account must clear this bar separately for every app it wants to take to production, though once *the account itself* has any production app, subsequent apps' requirements per current sourcing are less clear — **[UNVERIFIED]**, confirm current per-app vs. per-account scope directly in Play Console when the developer account is created, since Google has adjusted this program's exact mechanics multiple times since its 2023 introduction.
- Source: [Play Console Help: App testing requirements for new personal developer accounts](https://support.google.com/googleplay/android-developer/answer/14151465?hl=en) (indexed via search — **[UNVERIFIED-DIRECT]**, could not fetch directly this session), corroborated by [testerscommunity.com 12-Testers Policy Explained (2026)](https://www.testerscommunity.com/blog/google-play-12-testers-policy) and [primetestlab.com: 20 to 12 Testers](https://primetestlab.com/blog/google-play-changed-20-to-12-testers).

**Action item for Pen Fight:** find out now whether `bhanuteja-qae`'s Play Console account is a personal account created after 2023-11-13 — if so, budget at least 2 weeks of closed testing with 12 real opted-in Android testers (friends/family with real Google accounts, not emulators) before production access unlocks. Recruit them early; this is the single biggest schedule risk in the whole pipeline for a first-time solo publisher.

### Staged rollout

- Choose a percentage 1–100% when releasing to production (or to a test track). Increase manually over time.
- **Halt**: Play Console UI → release → "Manage rollout" → "Halt rollout" stops the percentage from growing further and can reduce exposure to the current cohort. Programmatically: `Edits.tracks.update` on the production track with the release's `status` set to `"halted"` via the [Play Developer API](https://developers.google.com/android-publisher/tracks).
- Once a rollout reaches 100%, it's final — you cannot roll a completed release back down; you'd need a new release to change behavior.
- Source: [Play Console Help: Release app updates with staged rollouts](https://support.google.com/googleplay/android-developer/answer/6346149?hl=en) (indexed — **[UNVERIFIED-DIRECT]**), [developers.google.com/android-publisher/tracks](https://developers.google.com/android-publisher/tracks) (API reference, standard/authoritative).

### Pre-launch report

Runs automatically against a real device farm when a release reaches a testing track (results attached to the release in Play Console). Catches: crashes, ANRs, use of deprecated/restricted APIs, security vulnerabilities, and (as warnings) slow startup, unsupported-but-not-yet-restricted API usage; plus lower-severity accessibility issues (missing content labels, low contrast, small touch targets). Provides per-device logcat, video capture, and stack traces. **Crashes found here do not count against your live Android vitals crash-rate stats** — it's a sandboxed pre-release check. Source: [Play Console Help: Understand your pre-launch report](https://support.google.com/googleplay/android-developer/answer/9844487) (indexed — **[UNVERIFIED-DIRECT]**).

### Review timelines (2026)

- Established developer accounts with prior approved apps: **1–3 days** typically.
- First-ever submission from a new account: commonly **7–14 days**, sometimes framed as "budget 2–3 weeks end-to-end" including identity verification and closed-testing review.
- Policy-sensitive categories (kids, health, finance, apps using AI features) can take longer; there is no paid expedite option.
- Any store-listing edit made while a review is pending can restart the review clock.
- **[UNVERIFIED-DIRECT]** — these figures come from third-party 2026 guides (lowcode.agency, ptkd.com, ontest.app), not fetched directly from `support.google.com`; treat as directional, not contractual, and pad the schedule.

### Developer registration fee and identity verification

- One-time **US$25** registration fee for a Play Console developer account (long-standing; not a subscription).
- **New 2026 development**: starting **September 2026**, Google is extending identity verification (document upload, sometimes a selfie) to developers distributing apps on certified Android devices more broadly, not just Play — verification can take a few hours up to 2 business days. The $25 fee is non-refundable even if verification fails.
- Sources: multiple 2026 guides converge on this (afkarsoftware.com, iconikai.com, testerbee.com, primetestlab.com); this is a fast-moving policy area for late 2026 — **verify directly against `support.google.com/googleplay/android-developer` at the time of registration**, since the September-2026 rollout may have moved or changed scope by the time Pen Fight registers. **[UNVERIFIED-DIRECT]**.

---

## 7. Automated upload to Play from CI

Three viable paths:

### a) Fastlane `supply`
- Standard, official-adjacent tool (part of the Fastlane project, widely used for Android release automation).
- Setup: enable Google Play Developer API in a Google Cloud project → create a Service Account → download its JSON key → invite that service-account email into Play Console (Users and permissions) with the right scoped permissions (below) → `fastlane run validate_play_store_json_key json_key:/path/to/file.json` to sanity check → reference via `Appfile`'s `json_key_file("path/to/play-store-credentials.json")` → `supply` action in a `Fastfile` uploads AAB + optional metadata/screenshots.
- Source: [fastlane docs: supply](https://docs.fastlane.tools/actions/supply/), [fastlane docs: Android setup](https://docs.fastlane.tools/getting-started/android/setup/).

### b) `r0adkll/upload-google-play` (GitHub Action)
- Latest release **v1.1.5, 2026-04-21** — after a long gap (last prior release Feb 2024), the project had a burst of releases in April 2026 (`v1.1.3` → `v1` → `v1.1.5` within days), suggesting renewed but possibly volatile maintenance. **Flag: verify it's not abandoned again before depending on it long-term; pin an exact SHA/tag rather than a floating major.**
- Inputs: `serviceAccountJson` (path) or `serviceAccountJsonPlainText` (secret contents), `packageName`, `releaseFiles` (glob for APK/AAB), `track`, plus staged-rollout %, per-locale release notes, and debug-symbol mapping upload.
- Wraps the same underlying Play Developer API supply mechanics as Fastlane, just as a native GH Action step (no Ruby/Fastlane toolchain needed) — simplest drop-in for a GitHub-Actions-first pipeline.

### c) Play Developer API directly
- Both (a) and (b) are convenience wrappers over `androidpublisher` v3 (`Edits.*` methods: `insert`, `apks.upload`/`bundles.upload`, `tracks.update`, `commit`). Calling it directly with `google-api-python-client` or similar is viable if you want full control, but for a solo dev, (a) or (b) is far less code to maintain.
- Reference: [Play Developer API: Getting Started](https://developers.google.com/android-publisher/getting_started).

### Service account setup and permissions (applies to all three options)

- Create the service account in Google Cloud Console, generate a JSON key, and **link it in Play Console**: Users and permissions → Invite new users → paste the service account email.
- **Least-privilege recommendation**: don't grant "Admin (all permissions)". Grant **App-level permissions** scoped to Pen Fight only: "View app information" (read-only baseline) + release-management permissions needed for your chosen tracks (e.g., "Release to testing tracks", "Release to production" only if CI actually pushes to production — otherwise keep production promotion manual). A "Release manager" style role (create/manage releases, no financial/user data access) is the closest built-in fit if your Play Console offers that named role; otherwise assemble the equivalent from individual app-level permissions.
- Source: [aso.dev: Google Play Console Permissions for Service Accounts](https://aso.dev/google-play/permissions/), [aso.dev: Roles for Service Accounts](https://aso.dev/google-play/roles/) — third-party but consistent with Play Console's actual permission-group UI; **[UNVERIFIED-DIRECT]** against `support.google.com`.

### The "first release must be manual" gotcha (confirmed, important)

**The Play Developer API can only modify an app that already has at least one release uploaded through the Play Console web UI.** You cannot bootstrap a brand-new app listing purely via API/CI. Practical sequence for Pen Fight:
1. Manually create the app in Play Console, fill in the store listing, and manually upload the **first** AAB (even to internal testing) once, by hand.
2. Only after that manual bootstrap will `supply`/`r0adkll`/raw-API calls succeed for all *subsequent* uploads.
Source: corroborated identically by [r0adkll/upload-google-play README](https://github.com/r0adkll/upload-google-play) ("the package name must already exist in the Play Console account") and multiple independent setup guides (appdrift.co, apppresser.com).

---

## 8. Crash reporting and analytics

### Options for Godot 4 Android (maturity assessed 2026-09-12 via release history)

| Option | Maintenance | Native (engine/JNI) crashes | GDScript errors | Setup effort | Forces custom Gradle build? |
|---|---|---|---|---|---|
| **Sentry Godot SDK** ([getsentry/sentry-godot](https://github.com/getsentry/sentry-godot)) | **Active, official (Sentry-owned).** Latest release `2.1.1`, **2026-08-03**; steady monthly cadence through 2026. Went 1.0 stable earlier in 2026 after an alpha/beta run starting mid-2025. Minimum supported Godot bumped to **4.5-stable** for the 1.x/2.x series — **not usable on older 4.x** without an older SDK release. | Yes — built as a GDExtension on top of `sentry-native`; captures native crashes on desktop platforms and (per SDK docs) mobile. | Yes — full GDScript stack traces as of the 4.5 beta era. | Low-moderate: GDExtension addon + a DSN, no Java plugin authored by you. | **[UNVERIFIED]** whether it requires Gradle "custom build" toggle on Android specifically — GDExtensions generally don't require it the way a Java/Kotlin Android plugin does, but confirm in the SDK's Android setup doc ([docs.sentry.io/platforms/godot/configuration/android](https://docs.sentry.io/platforms/godot/configuration/android/)) since it wasn't independently fetched this session. |
| **Firebase Crashlytics via Godot Android plugin** — two candidates found: `DrMoriarty/godot-firebase-crashlytics` (stale — last known version targets **Godot 3.3**, not 4) and `godot-x/firebase` (targets **Godot 4.5-stable**, active — releases through `3.1.0` on **2026-07-22**, steady cadence since early 2026). | `DrMoriarty` version: **abandoned for Godot 4 purposes** — do not use. `godot-x/firebase`: actively maintained as of check date, but comparatively young (first releases visible from Jan 2026) — **less battle-tested than Sentry's SDK**. | Yes, in principle — Crashlytics natively captures JVM/native Android crashes; whether the Godot bridge forwards *engine-level native* crashes (vs. only Java-layer ones) is **[UNVERIFIED]**, check the plugin's own docs/issues before relying on it for GDScript crash visibility. | Depends entirely on the bridge code reporting non-fatal GDScript errors to Crashlytics manually — not automatic the way it is for JVM exceptions. **[UNVERIFIED]** without reading the plugin source. | Moderate-high: it's a real Android plugin (Java/Kotlin `.aar` + `google-services.json`), meaning real Gradle/Firebase project setup. | **Yes** — Android Java/Kotlin plugins require `gradle_build/use_gradle_build=true` and typically the custom-build path in the export preset, per Godot's own Android plugin architecture. |
| **Homegrown crash handler** (GDScript-level `push_error`/`OS.crash` hooks, or Godot 4's built-in crash-handler + log capture, shipped to your own backend) | N/A (yours to maintain) | **No** — a pure-GDScript handler cannot intercept native/engine crashes (segfaults, JNI crashes) that kill the process before script code can run; it can only catch GDScript-level runtime errors it's wired to observe. | Yes, for whatever you explicitly wrap. | Low effort but low coverage. | No. |

**Recommendation for a solo dev on Godot 4.7.2**: Sentry's Godot SDK is currently the most credible option — official vendor backing, real release cadence, GDScript stack traces, no Gradle custom-build requirement for the addon itself. Its hard floor of **Godot 4.5-stable** is compatible with the pinned `4.7.2-stable` used above. Treat Firebase-via-community-plugin as a fallback only if you also want Firebase Analytics/Remote Config and are willing to take on a real Gradle custom build; the `godot-x/firebase` project is promising but too new to call "mature" with confidence.

### Play Console's free built-in signal: Android vitals

No SDK needed — Play automatically aggregates crash/ANR telemetry from the OS itself for any app on Play. "Bad behavior" thresholds Google currently documents (exceeding these can reduce your store visibility and/or trigger an in-listing warning to users):

- **User-perceived crash rate**: bad-behavior threshold at **1.09%** of daily active users experiencing a crash (aggregate, across all devices); **8%** for any single device model.
- **User-perceived ANR rate**: bad-behavior threshold at **0.47%** of daily active users (aggregate); **8%** for any single device model.

Source: [developer.android.com/topic/performance/vitals](https://developer.android.com/topic/performance/vitals) and [Android Developers Blog: Raising the bar on technical quality on Google Play (2022)](https://android-developers.googleblog.com/2022/10/raising-bar-on-technical-quality-on-google-play.html) — these are the numbers Google itself has published and are widely re-cited through 2026; **treat the exact percentages as [UNVERIFIED-DIRECT]** since the primary Android Developers pages were reached via search-index summary rather than a direct fetch this session (only `support.google.com` was proxy-blocked; `developer.android.com` links appeared in results but weren't independently WebFetched) — re-confirm the numbers on `developer.android.com/topic/performance/vitals` before treating them as a hard commitment, since Google has previously revised these thresholds.

---

## 9. Play Billing (remove-ads IAP) and AdMob on Godot 4

### Godot Google Play Billing plugin

- Repo: [godot-sdk-integrations/godot-google-play-billing](https://github.com/godot-sdk-integrations/godot-google-play-billing) — this org (`godot-sdk-integrations`) is the community-adopted successor/home for several official-adjacent Godot Android plugins.
- **Actively maintained**: latest release `3.3.0`, **2026-07-27**; steady release history through 2025–2026 (3.0/3.1 in Oct 2025, 2.0 in July 2025, wraps an underlying Google Play Billing Library version bump each major).
- Requires enabling **Gradle build** (`gradle_build/use_gradle_build=true`) in the Android export preset — it is a real Android/Java plugin, not a pure GDExtension.
- Docs site: [godot-sdk-integrations.github.io/godot-google-play-billing](https://godot-sdk-integrations.github.io/godot-google-play-billing/), install docs at [.../installation.html](https://godot-sdk-integrations.github.io/godot-google-play-billing/installation.html).
- Also spotted an alternative, `code-with-max`/`thunderplugins`-style commercial/itch.io plugin claiming Billing v7/v8 support for Godot 4.6+ — **not evaluated for maturity**, treat as unverified alternative; the `godot-sdk-integrations` plugin above is the safer default given its release cadence and org backing.

### Integration shape for a single non-consumable "remove ads" product

1. Create the in-app product in Play Console (Monetize → Products → In-app products) as a **managed product** (non-consumable, one-time purchase), e.g. SKU `remove_ads`.
2. In-game: call the plugin's query-products / launch-purchase-flow methods, listen for the purchase-updated signal.
3. **Acknowledge the purchase** (`BillingClient.acknowledgePurchase()`-equivalent exposed by the plugin) **within 3 days** of the purchase completing. Google Play **automatically refunds and revokes entitlement** for any purchase (Billing Library v2+) that isn't acknowledged in that window — this applies to non-consumables too, not just subscriptions. Source: [Android Developers: One-time purchase lifecycle](https://developer.android.com/google/play/billing/lifecycle/one-time) (indexed — **[UNVERIFIED-DIRECT]**, consistent across multiple independent write-ups including a real bug report of unacknowledged-subscription auto-refunds: [jamesmontemagno/InAppBillingPlugin#673](https://github.com/jamesmontemagno/InAppBillingPlugin/issues/673)).
4. **Restore/entitlement check on fresh install**: on every app start (or at least once post-install), call the equivalent of `queryPurchasesAsync` for the `INAPP` product type and re-apply entitlement locally if `remove_ads` shows as owned — Play does not "push" ownership to a fresh install automatically; the app must query and re-grant it. Store the boolean locally (e.g. in `user://` save data) after that check so ads stay off without a network call every launch.
5. **Testing**: add tester Gmail addresses under **Play Console → Setup → License testing**; those accounts see Play's test payment instruments (a "test card" that always approves) instead of real charges when purchasing *from a build installed via any test track* (internal/closed/open) — the app must have been uploaded to at least one test track once for license testing to activate. Source: [Android Developers: Test your Google Play Billing Library integration](https://developer.android.com/google/play/billing/test) (indexed — **[UNVERIFIED-DIRECT]**), corroborated by [RevenueCat's Play Billing testing guide](https://www.revenuecat.com/guides/google-play-billing/testing-your-integration).

### AdMob plugin

- Repo: [poingstudios/godot-admob-plugin](https://github.com/poingstudios/godot-admob-plugin) (umbrella) with platform repos [godot-admob-android](https://github.com/poingstudios/godot-admob-android) / `-ios`.
- **Actively maintained**: reported updated **2026-08-22**; supports Godot 4.2+ with GDScript/C# parity, in-editor mock ads for layout testing, and current Google Mobile Ads SDK mediation adapters.
- Also a real Android plugin → requires Gradle build, same as the Billing plugin (both can share one custom Gradle build).
- **Play/AdMob policy constraint on interstitials** (current, actively enforced): showing an interstitial **immediately on app load or on app exit is disallowed**; interstitials must sit at natural content-transition breaks, not interrupt a task the user is mid-action on, since that risks "accidental click" policy strikes. On apps targeting **API level 35**, the interstitial close button can be effectively hidden if not handled correctly by the SDK version — keep the AdMob SDK current to avoid this. Source: [AdMob Help: Interstitial ad guidance](https://support.google.com/admob/answer/6066980), [Disallowed interstitial implementations](https://support.google.com/admob/answer/6201362?hl=en) — both indexed via search, **[UNVERIFIED-DIRECT]**.

**Combined Gradle note**: since both the Billing plugin and AdMob plugin require `gradle_build/use_gradle_build=true`, plan for a single custom Gradle Android build from the start rather than the default "no Gradle" export path — this changes nothing about the CI workflow in §2 (Docker image already includes JDK/Android SDK) but does mean local dev builds also need Android Studio/Gradle set up, not just the editor's built-in exporter.

---

## 10. Testing workflow

### What's automatable for a Godot game

| Framework | Latest state | Runs headless in CI? |
|---|---|---|
| **GUT (Godot Unit Test)** — [bitwes/Gut](https://github.com/bitwes/Gut) | Community-maintained, MIT. Godot 4.x tracked by GUT 9.x (main branch → Godot 4.6.x; a `godot_4_7` branch exists for 4.7.x) — check branch/version alignment against your pinned `4.7.2-stable` before adopting. | Yes — CLI runner + JUnit XML export designed for CI; needs the same import warm-up trick as export (`--headless --editor --quit --import`, run twice) plus `GODOT_DISABLE_LEAK_CHECKS=1` to avoid false failures from engine leak-check noise on headless runs (per a 2026 write-up: [CI-tested GUT for Godot 4](https://medium.com/@kpicaza/ci-tested-gut-for-godot-4-fast-green-and-reliable-c56f16cde73d)). |
| **GdUnit4** — [godot-gdunit-labs/gdUnit4](https://github.com/godot-gdunit-labs/gdUnit4) | Active; has its own `GdUnitCmdTool.gd` CLI entry, HTML + JUnit XML report export, a published GitHub Marketplace action, and a scene-runner utility that can simulate input (clicks, key presses, touch) for higher-level scripted scenarios. | Yes — `godot --headless --ignoreHeadlessMode -- <GdUnitCmdTool args>`-style invocation documented for CI. |

Both are viable; GdUnit4 has the more modern feature set (scene runner, richer mocking) and its own GH Action, GUT has the longer community track record. Either is fine for a solo project — pick one and don't run both.

### Why physics-dependent behavior resists unit testing

Godot's physics (`PhysicsServer2D`/`3D`) runs on the engine's own fixed-step simulation loop tied to frame processing; deterministic, isolated assertions about "does the pen land correctly" or "does a collision resolve the way it looks" require either (a) driving multiple physics frames forward in a running SceneTree (which GUT/GdUnit4 scene-runners can do, but slowly and with tolerance-based, not exact, assertions — floating point + solver iteration counts make bit-exact expectations fragile), or (b) accepting that visual/feel correctness for physics-driven mechanics is fundamentally a playtesting concern, not a unit-testing one. This is a real, structural limitation, not a tooling gap — it applies equally to GUT and GdUnit4.

### Recommended split for Pen Fight's turn/score state machine

- **Put the turn/score/game-state logic in plain GDScript classes with no scene-tree or physics dependency** (pure `RefCounted`/`Resource`-based state machine: `TurnManager`, `ScoreTracker`, `MatchState`, etc., taking data in and returning data out, not reading `Input` or `PhysicsServer` directly). This is exactly the kind of code GUT/GdUnit4 unit test well: deterministic, synchronous, no frame stepping required.
- **Keep physics/visual behavior (pen trajectory, collision response, aiming feel) as a thin adapter layer** that calls into the pure logic and is validated by playtesting, not asserted in CI. If you want *some* automated coverage here, GdUnit4's scene-runner can smoke-test "the scene loads, physics doesn't crash, a shot registers *a* collision" — but treat that as a regression smoke test, not a correctness test of "does it feel right."
- Concretely: if the turn/score state machine currently lives inside a `Node`/scene script reacting to physics signals, that's the thing to refactor out first — it's what makes the difference between "this is testable" and "this isn't," independent of which framework you pick.

---

## 11. Recommended end-state workflow (day-to-day sequence)

1. **Branch**: create a feature branch off `main` for the change (`git checkout -b feature/x`).
2. **Local test**: run the unit test suite locally in the editor or via CLI (`godot --headless -s addons/gut/gut_cmdln.gd` or GdUnit4's equivalent) against the pure-logic layer (§10) before committing; playtest physics/feel changes manually in the editor.
3. **Push + CI checks**: push the branch, let a lightweight CI job (GitHub Actions/GitLab CI, no tag needed) run: headless import warm-up → unit tests → (optionally) a debug export as a smoke check that the project still exports. This job runs on every push/PR, is fast, and never touches signing secrets.
4. **Merge to `main`** once CI is green and (for solo dev) self-review is done.
5. **Tag a release** when ready to ship: `git tag v1.4.2 && git push origin v1.4.2` — this is the single manual trigger for everything downstream, matching the "a git tag produces an installable build with no manual steps" goal.
6. **CI builds the signed AAB** automatically on the tag push (§2/§3): version derived from the tag, keystore injected from secrets, AAB attached to a GitHub Release / GitLab job artifact.
7. **Push to internal testing track**: either as an automatic step in the same tag-triggered pipeline (via `supply`/`r0adkll`/API — safe to fully automate, since internal testing has no review and no user-facing risk) or a one-click manual promotion the first few times until you trust the pipeline. Recommendation: automate up to **internal testing only**; keep closed/production promotion a manual Play Console click for a solo dev, since those have real user/reviewer consequences.
8. **On devices**: install from the internal testing opt-in link on your own and any co-tester devices; verify the actual APK/AAB installs and runs (this also exercises Play's own signing round-trip, not just your local build).
9. **Promote to closed testing** (required track for the 12-tester/14-day production-access requirement, §6) once internal testing looks good; recruit and keep your 12 testers continuously opted in for the required window.
10. **Promote to production** with a staged rollout (start at 5–20%), watching Android vitals (crash rate, ANR rate — thresholds in §8) and the pre-launch report for that release; halt the rollout immediately if crash/ANR climbs, before increasing to 100%.
11. **Repeat from step 1** for the next change; hotfixes follow the same tag → CI → internal → (skip to production if already-tested closed testers exist and this is a low-risk fix) path, with versionCode still monotonic per §4 regardless of which branch the hotfix came from.

---

## Sources index (all fetched or searched 2026-09-12)

- Godot export/CI issues: [godotengine/godot#78412](https://github.com/godotengine/godot/issues/78412), [#69511](https://github.com/godotengine/godot/issues/69511), [#71521](https://github.com/godotengine/godot/issues/71521), [#73782](https://github.com/godotengine/godot/issues/73782), [#77508](https://github.com/godotengine/godot/issues/77508), [#83449](https://github.com/godotengine/godot/issues/83449), [#109551](https://github.com/godotengine/godot/issues/109551), [#94815](https://github.com/godotengine/godot/issues/94815), [#85898](https://github.com/godotengine/godot/issues/85898), [PR #35930](https://github.com/godotengine/godot/pull/35930), [godot-proposals#1156](https://github.com/godotengine/godot-proposals/issues/1156), [godot-proposals#749](https://github.com/godotengine/godot-proposals/issues/749)
- [Android Developers: Export Godot projects to Android](https://developer.android.com/games/engines/godot/godot-export)
- [Android Developers: Version your app](https://developer.android.com/studio/publish/versioning)
- [Android Developers: One-time purchase lifecycle](https://developer.android.com/google/play/billing/lifecycle/one-time)
- [Android Developers: Test your Google Play Billing Library integration](https://developer.android.com/google/play/billing/test)
- [Android Developers: Android vitals](https://developer.android.com/topic/performance/vitals)
- [Android Developers Blog: Raising the bar on technical quality (2022)](https://android-developers.googleblog.com/2022/10/raising-bar-on-technical-quality-on-google-play.html)
- [abarichello/godot-ci](https://github.com/abarichello/godot-ci) + releases.atom (2026-08-22 latest)
- [firebelley/godot-export](https://github.com/firebelley/godot-export) + releases.atom (2026-05-28 latest)
- [chickensoft-games/setup-godot](https://github.com/chickensoft-games/setup-godot) + releases.atom (2026-08-28 latest)
- [r0adkll/upload-google-play](https://github.com/r0adkll/upload-google-play) + releases.atom (2026-04-21 latest)
- [getsentry/sentry-godot](https://github.com/getsentry/sentry-godot) + releases.atom (2026-08-03 latest), [docs.sentry.io/platforms/godot](https://docs.sentry.io/platforms/godot/configuration/)
- [DrMoriarty/godot-firebase-crashlytics](https://github.com/DrMoriarty/godot-firebase-crashlytics) (stale, Godot 3.3 only)
- [godot-x/firebase](https://github.com/godot-x/firebase) + releases.atom (2026-07-22 latest)
- [godot-sdk-integrations/godot-google-play-billing](https://github.com/godot-sdk-integrations/godot-google-play-billing) + releases.atom (2026-07-27 latest)
- [poingstudios/godot-admob-plugin](https://github.com/poingstudios/godot-admob-plugin)
- [bitwes/Gut](https://github.com/bitwes/Gut), [godot-gdunit-labs/gdUnit4](https://github.com/godot-gdunit-labs/gdUnit4)
- [fastlane docs: supply](https://docs.fastlane.tools/actions/supply/), [fastlane Android setup](https://docs.fastlane.tools/getting-started/android/setup/)
- [developers.google.com/android-publisher (Getting Started, tracks)](https://developers.google.com/android-publisher/getting_started)
- Play Console Help pages (14151465 testing requirements, 9845334 test tracks, 9842756 App Signing, 6346149 staged rollouts, 9844487 pre-launch report) — all **indexed via WebSearch, not directly WebFetched** this session (`support.google.com` was proxy-blocked); treat exact wording/numbers as reported-not-verified pending a direct re-check.
- Third-party 2026 policy trackers used for corroboration only (not sole source for any hard number): testerscommunity.com, primetestlab.com, ontest.app, afkarsoftware.com, iconikai.com, aso.dev, envmanager.com.

## Flags summary

- **[UNVERIFIED-DIRECT]**: any claim sourced only from `support.google.com`, `docs.godotengine.org`, or `game.ci` pages that this session could not fetch directly (proxy-blocked) — re-verify against the live page before treating as contractual, especially the 14-day/12-tester scope, App Signing reset SLA, pre-launch report contents, and the exact Android-vitals percentage thresholds.
- **[UNVERIFIED]**: specific technical claims not independently confirmed by reading source/docs this session — GitLab File-variable exact runtime semantics, whether Sentry-Godot/Crashlytics-bridge forwards true native engine crashes vs. only JVM-layer ones, whether Sentry's Android integration needs Gradle custom build, and `git tag --merged HEAD` behaving correctly across all of Pen Fight's future branching patterns.
- **Maintenance risk flagged per plugin**: `r0adkll/upload-google-play` (long dormancy before an April-2026 burst — pin exact commit/tag, watch for renewed abandonment); `DrMoriarty/godot-firebase-crashlytics` (dead for Godot 4, don't use); `godot-x/firebase` (active but young, less proven than Sentry); everything else in the comparison tables above currently shows healthy, ongoing maintenance as of 2026-09-12.

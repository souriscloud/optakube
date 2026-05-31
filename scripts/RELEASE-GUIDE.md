# OptaKube Release Guide

The release pipeline (`scripts/release.sh`) is fully automated and self-guarding:
it runs preflight checks, builds, signs, notarizes, generates the Sparkle
appcast (with delta updates), commits, tags, and publishes the GitHub release.
OptaKube ships a single **stable** channel.

## One-time setup

1. **GitHub CLI** authenticated:
   ```bash
   gh auth login
   ```

2. **Sparkle EdDSA key** in the login Keychain (one-time, org-wide — the same key
   signs every souris.cloud app's updates; back it up, never regenerate without a
   migration plan):
   ```bash
   swift build   # fetches Sparkle's tools into .build/
   .build/artifacts/sparkle/Sparkle/bin/generate_keys        # only if not present
   .build/artifacts/sparkle/Sparkle/bin/generate_keys -p     # prints the public key
   ```
   The public key lives in `Sources/OptaKube/Info.plist` as `SUPublicEDKey`.

3. **Notary credentials** stored as a keychain profile (one-time). Without this,
   preflight fails with a copy-pasteable hint:
   ```bash
   xcrun notarytool store-credentials "notarytool" \
       --apple-id <APPLE_ID> --team-id <TEAM_ID> \
       --password <app-specific-password>   # from appleid.apple.com
   ```

4. **`scripts/.env`** (gitignored) with the signing config. Copy the template and
   fill it in:
   ```bash
   cp scripts/.env.example scripts/.env
   # TEAM_ID, CODESIGN_IDENTITY, APPLE_ID, NOTARYTOOL_PROFILE, GITHUB_REPO
   ```
   Find your codesign identity with `security find-identity -v -p codesigning`.

## Release process

1. **Land all changes and update `CHANGELOG.md`.** Move items from
   `## [Unreleased]` into a new `## [X.Y.Z] - YYYY-MM-DD` section. Commit
   everything — the release script **requires a clean working tree**.

2. **Rehearse (optional but recommended).** No Apple creds or network needed:
   ```bash
   ./scripts/release.sh --dry-run --skip-notarize X.Y.Z
   ```
   Builds, EdDSA-signs the DMG, and writes the appcast into
   `.build/release-build/` for inspection. The version bump is auto-reverted on
   exit, so the tree is left untouched.

3. **Release:**
   ```bash
   ./scripts/release.sh X.Y.Z
   ```

The script will:
- **Preflight:** `gh` auth, codesign identity, notary profile (with verbatim
  Apple errors), Sparkle key, `swift test`, clean tree, and that `vX.Y.Z` is free.
- Bump the version in `AboutView.swift` + `Info.plist` (build number derived as
  `major*10000 + minor*100 + patch`). A trap **reverts the bump** if anything
  fails before the commit.
- Build, bundle the `.app` with `Sparkle.framework`, codesign (nested helpers →
  framework → app), build the styled DMG, then **notarize + staple** — a notary
  rejection is a **hard failure** (nothing is committed or published).
- Run `generate_appcast` over `releases/` to produce a signed `appcast.xml`
  **with delta updates**, then rewrite each enclosure/delta URL to point at its
  own version's GitHub tag.
- Stage **only** `AboutView.swift`, `Info.plist`, `CHANGELOG.md`, and
  `appcast.xml`; commit, tag `vX.Y.Z`, push.
- Create the GitHub release with the DMG (and any delta files) attached.

4. **Verify:** open the [releases page](https://github.com/souriscloud/optakube/releases),
   download the DMG, and confirm auto-update from the prior version.

## Appcast & deltas

Sparkle reads `SUFeedURL` (→ `appcast.xml` on the default branch) and
`SUPublicEDKey` from `Info.plist`. `generate_appcast` reads the DMGs in
`releases/` to build the feed and compute binary deltas between versions. That
dir is gitignored — it's a large local DMG store; only the generated
`appcast.xml` is committed. Deltas only span versions present locally, so a fresh
clone starts delta history from its first release there.

## Version numbering

- **Major** (X.0.0) — breaking changes, major redesign
- **Minor** (0.X.0) — new features, resource types, UI improvements
- **Patch** (0.0.X) — bug fixes, polish

## Scripts

| Script | Description |
|--------|-------------|
| `scripts/release.sh [--dry-run] [--skip-notarize] <version>` | Full release automation |
| `scripts/download-stats.sh` | Download counts per release |
| `scripts/create-dmg-background.swift` | Generates the DMG background image |

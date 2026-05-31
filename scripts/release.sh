#!/bin/bash
set -euo pipefail

# OptaKube Release Script
# Usage: ./scripts/release.sh [--dry-run] [--skip-notarize] <version>
# Example: ./scripts/release.sh 0.8.0
#
# Pipeline:
#   0. Preflight  — .env creds, gh auth, codesign identity, notary profile,
#                   Sparkle key, `swift test`, clean tree, tag is free
#   1. Bump version (AboutView.swift + Info.plist); rollback trap arms here
#   2. Build release binary
#   3. Assemble .app bundle (+ Sparkle.framework)
#   4. Codesign (nested Sparkle helpers → framework → app)
#   5. Build styled DMG
#   6. Codesign + notarize + staple the DMG  (hard fail on rejection)
#   7. generate_appcast over releases/ → signed appcast.xml + deltas
#   8. Commit (targeted), tag, push
#   9. GitHub release with the DMG (+ delta files) attached
#
# Flags:
#   --dry-run        build/sign/notarize/generate locally, but DON'T touch the
#                    committed appcast, git, or GitHub. Writes the appcast to the
#                    build dir for inspection. Clean-tree/tag checks downgrade to
#                    warnings so you can rehearse on a dirty tree.
#   --skip-notarize  skip the Apple notarization round-trip (the slow, network +
#                    Apple-ID part) only. The app/DMG are STILL codesigned with the
#                    local Developer ID cert — generate_appcast requires a signed
#                    app, so a rehearsal must sign even when it doesn't notarize.

DRY_RUN=0; SKIP_NOTARIZE=0
POSITIONAL=()
while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run|-n) DRY_RUN=1; shift ;;
        --skip-notarize) SKIP_NOTARIZE=1; shift ;;
        -h|--help) echo "Usage: $0 [--dry-run] [--skip-notarize] <version>"; exit 0 ;;
        *) POSITIONAL+=("$1"); shift ;;
    esac
done
set -- "${POSITIONAL[@]:-}"

VERSION="${1:-}"
[ -n "$VERSION" ] || { echo "Usage: $0 [--dry-run] [--skip-notarize] <version>"; exit 1; }
echo "$VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$' || { echo "ERROR: version must be MAJOR.MINOR.PATCH (got: $VERSION)"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$ROOT_DIR"

# ── Credentials (.env) — RELIMPR #1 ──
ENV_FILE="$SCRIPT_DIR/.env"
[ -f "$ENV_FILE" ] || { echo "ERROR: $ENV_FILE not found. Copy scripts/.env.example and fill it in."; exit 1; }
# shellcheck source=scripts/.env
source "$ENV_FILE"
chmod 600 "$ENV_FILE" 2>/dev/null || true
for var in TEAM_ID CODESIGN_IDENTITY APPLE_ID NOTARYTOOL_PROFILE GITHUB_REPO; do
    [ -n "${!var:-}" ] || { echo "ERROR: $var is not set in $ENV_FILE"; exit 1; }
done

APP_NAME="OptaKube"
BUILD_DIR="$ROOT_DIR/.build/release-build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
DMG_NAME="$APP_NAME-$VERSION.dmg"
DMG_PATH="$BUILD_DIR/$DMG_NAME"
GIT_BRANCH="master"

# Local DMG store feeding generate_appcast's delta computation (gitignored).
# Under --dry-run we keep it in the build dir so a rehearsal never mutates the
# persistent store or the committed appcast.
if [ "$DRY_RUN" = "1" ]; then
    RELEASES_DIR="$BUILD_DIR/releases"; APPCAST_OUT="$BUILD_DIR/appcast.xml"
else
    RELEASES_DIR="$ROOT_DIR/releases"; APPCAST_OUT="$ROOT_DIR/appcast.xml"
fi

echo "=== OptaKube Release $VERSION ==="
[ "$DRY_RUN" = 1 ] && echo "*** DRY RUN — no git/gh/appcast changes; artifacts in $BUILD_DIR ***"
[ "$SKIP_NOTARIZE" = 1 ] && echo "*** SKIP-NOTARIZE — no codesign/notarization (DMG still EdDSA-signed) ***"

# Locate the Sparkle CLI tools (generate_appcast, sign_update, generate_keys).
SPARKLE_BIN=""
for d in "$ROOT_DIR/.build/artifacts/sparkle/Sparkle/bin" "$ROOT_DIR/.build/checkouts/Sparkle/bin"; do
    [ -x "$d/generate_appcast" ] && { SPARKLE_BIN="$d"; break; }
done

# ── 0. Preflight — RELIMPR #2/#7 ──
echo ""; echo "→ Preflight"
fail() { echo "  ✗ $1"; exit 1; }

if [ "$DRY_RUN" = 0 ]; then
    command -v gh >/dev/null 2>&1 || fail "GitHub CLI 'gh' not installed."
    gh auth status >/dev/null 2>&1 || fail "gh not authenticated. Run: gh auth login"
fi

# Codesigning is always required (generate_appcast needs a signed app); it uses
# only the local Developer ID cert, no Apple round-trip.
security find-identity -v -p codesigning | grep -q "$CODESIGN_IDENTITY" \
    || fail "Codesigning identity not found: $CODESIGN_IDENTITY"

if [ "$SKIP_NOTARIZE" = 0 ]; then
    # Capture stderr so an agreement/billing problem surfaces verbatim rather
    # than being flattened to a generic "profile missing".
    NOTARY_OUT=$(xcrun notarytool history --keychain-profile "$NOTARYTOOL_PROFILE" 2>&1 || true)
    if echo "$NOTARY_OUT" | grep -qi "error"; then
        echo "$NOTARY_OUT" >&2
        if echo "$NOTARY_OUT" | grep -qi "agreement"; then
            fail "Apple Developer agreement needs accepting at https://appstoreconnect.apple.com/agreements/ then rerun."
        elif echo "$NOTARY_OUT" | grep -qi "no keychain item"; then
            fail "Notary profile '$NOTARYTOOL_PROFILE' missing. Run: xcrun notarytool store-credentials \"$NOTARYTOOL_PROFILE\" --apple-id $APPLE_ID --team-id $TEAM_ID --password <app-pw>"
        else
            fail "notarytool preflight failed — see message above."
        fi
    fi
fi

[ -n "$SPARKLE_BIN" ] || { echo "  Sparkle tools missing — running swift build to fetch them"; swift build >/dev/null; for d in "$ROOT_DIR/.build/artifacts/sparkle/Sparkle/bin" "$ROOT_DIR/.build/checkouts/Sparkle/bin"; do [ -x "$d/generate_appcast" ] && { SPARKLE_BIN="$d"; break; }; done; }
[ -n "$SPARKLE_BIN" ] || fail "Could not locate Sparkle's generate_appcast."
"$SPARKLE_BIN/generate_keys" -p >/dev/null 2>&1 || fail "Sparkle EdDSA private key missing from Keychain. Run: $SPARKLE_BIN/generate_keys"

echo "  Running tests…"
# Rely on swift test's exit code (piping to grep would mask it; the swift-testing
# runner prints "passed" for its 0 tests even when XCTest cases fail).
if swift test >/tmp/optakube-test.log 2>&1; then
    echo "  ✓ tests passed"
else
    tail -20 /tmp/optakube-test.log
    fail "Tests failed — aborting release."
fi

if ! git diff --quiet || ! git diff --cached --quiet; then
    [ "$DRY_RUN" = 1 ] && echo "  ⚠ working tree dirty (allowed in dry-run)" || fail "Working tree has uncommitted changes. Commit or stash first."
fi
if git rev-parse "v$VERSION" >/dev/null 2>&1; then
    [ "$DRY_RUN" = 1 ] && echo "  ⚠ tag v$VERSION already exists (allowed in dry-run)" || fail "Git tag v$VERSION already exists. Pick a new version."
fi
echo "  ✓ preflight passed"

# ── 1. Bump version (+ rollback trap) ──
echo ""; echo "→ [1/9] Bumping version"
python3 - "$VERSION" <<'PY'
import re, sys
v = sys.argv[1]
major, minor, patch = (int(x) for x in v.split('.'))
build = major * 10000 + minor * 100 + patch
for path, subs in {
    'Sources/OptaKube/Views/Settings/AboutView.swift': [
        (r'(static let version = ")[^"]*(")', rf'\g<1>{v}\g<2>')],
    'Sources/OptaKube/Info.plist': [
        (r'(<key>CFBundleShortVersionString</key>\s*<string>)[^<]*(</string>)', rf'\g<1>{v}\g<2>'),
        (r'(<key>CFBundleVersion</key>\s*<string>)\d+(</string>)', rf'\g<1>{build}\g<2>')],
}.items():
    s = open(path).read()
    for pat, rep in subs: s = re.sub(pat, rep, s)
    open(path, 'w').write(s)
print(f'  v{v} (build {build})')
PY
BUILD_NUM=$(python3 -c "import re; print(re.search(r'<key>CFBundleVersion</key>\s*<string>(\d+)</string>', open('Sources/OptaKube/Info.plist').read()).group(1))")

VERSION_FILES=("Sources/OptaKube/Views/Settings/AboutView.swift" "Sources/OptaKube/Info.plist")
RELEASE_COMMITTED=0
revert_on_abort() {
    [ "$RELEASE_COMMITTED" = 1 ] && return
    git checkout -- "${VERSION_FILES[@]}" 2>/dev/null && echo "Reverted version bump (release aborted before commit)." >&2 || true
}
trap revert_on_abort EXIT

# ── 2. Build ──
echo ""; echo "→ [2/9] Building"
rm -rf "$BUILD_DIR"; mkdir -p "$BUILD_DIR"
swift build -c release 2>&1 | tail -3
BINARY_PATH="$ROOT_DIR/.build/release/$APP_NAME"
[ -f "$BINARY_PATH" ] || fail "Build failed"

# ── 3. Assemble .app ──
echo ""; echo "→ [3/9] Assembling .app"
mkdir -p "$APP_DIR/Contents/"{MacOS,Resources,Frameworks}
cp "$BINARY_PATH" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp "Sources/OptaKube/Info.plist" "$APP_DIR/Contents/Info.plist"
[ -f "Sources/OptaKube/Resources/AppIcon.icns" ] && cp "Sources/OptaKube/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/"
[ -d "$ROOT_DIR/.build/release/OptaKube_OptaKube.bundle" ] && cp -R "$ROOT_DIR/.build/release/OptaKube_OptaKube.bundle" "$APP_DIR/Contents/Resources/"
for fw in "$ROOT_DIR/.build/arm64-apple-macosx/release/Sparkle.framework" \
          "$ROOT_DIR/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"; do
    [ -d "$fw" ] && { cp -R "$fw" "$APP_DIR/Contents/Frameworks/"; break; }
done
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP_DIR/Contents/MacOS/$APP_NAME" 2>/dev/null || true

# ── 4. Codesign (always — generate_appcast needs a signed app) ──
echo ""; echo "→ [4/9] Codesigning"
cat > "$BUILD_DIR/entitlements.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.network.client</key><true/>
    <key>com.apple.security.files.user-selected.read-write</key><true/>
    <key>com.apple.security.cs.allow-unsigned-executable-memory</key><true/>
</dict>
</plist>
EOF
# Sign nested Sparkle helpers first (deepest → shallowest), then the app —
# the modern non-`--deep` approach Apple's notary service expects.
SPKB="$APP_DIR/Contents/Frameworks/Sparkle.framework/Versions/B"
for t in "$SPKB/XPCServices/Downloader.xpc" "$SPKB/XPCServices/Installer.xpc" \
         "$SPKB/Autoupdate" "$SPKB/Updater.app" \
         "$APP_DIR/Contents/Frameworks/Sparkle.framework"; do
    [ -e "$t" ] && codesign --force --options runtime --timestamp --sign "$CODESIGN_IDENTITY" "$t"
done
codesign --force --options runtime --timestamp --entitlements "$BUILD_DIR/entitlements.plist" --sign "$CODESIGN_IDENTITY" "$APP_DIR"
codesign --verify --strict --verbose=2 "$APP_DIR" && echo "  ✓ signed" || fail "codesign verify failed"

# ── 5. Build DMG ──
echo ""; echo "→ [5/9] Building DMG"
DMG_STAGING="$BUILD_DIR/dmg-staging"; DMG_TEMP="$BUILD_DIR/temp.dmg"
rm -rf "$DMG_STAGING" "$DMG_TEMP" "$DMG_PATH"
mkdir -p "$DMG_STAGING/.background"
swift "$SCRIPT_DIR/create-dmg-background.swift" "$DMG_STAGING/.background/background.png" 2>/dev/null || true
cp -R "$APP_DIR" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_STAGING" -ov -format UDRW "$DMG_TEMP" 2>/dev/null
MOUNT_DIR=$(hdiutil attach "$DMG_TEMP" -readwrite -noverify 2>/dev/null | grep "/Volumes/" | sed 's/.*\/Volumes/\/Volumes/')
[ -n "$MOUNT_DIR" ] && {
    osascript <<AS || true
    tell application "Finder"
        tell disk "$APP_NAME"
            open
            set current view of container window to icon view
            set toolbar visible of container window to false
            set statusbar visible of container window to false
            set bounds of container window to {200, 200, 860, 600}
            set opts to the icon view options of container window
            set arrangement of opts to not arranged
            set icon size of opts to 96
            set background picture of opts to file ".background:background.png"
            set position of item "$APP_NAME.app" of container window to {165, 180}
            set position of item "Applications" of container window to {495, 180}
            close
            open
            update without registering applications
            delay 1
            close
        end tell
    end tell
AS
    sync; hdiutil detach "$MOUNT_DIR" 2>/dev/null || true
}
hdiutil convert "$DMG_TEMP" -format UDZO -imagekey zlib-level=9 -o "$DMG_PATH" 2>/dev/null
rm -f "$DMG_TEMP"; rm -rf "$DMG_STAGING"
echo "  $(du -h "$DMG_PATH" | cut -f1)"

# ── 6. Sign DMG, then notarize + staple (hard fail — RELIMPR #4) ──
echo ""; echo "→ [6/9] Notarizing DMG"
codesign --force --sign "$CODESIGN_IDENTITY" "$DMG_PATH"
if [ "$SKIP_NOTARIZE" = 0 ]; then
    NOTARIZE_OUT=$(xcrun notarytool submit "$DMG_PATH" --apple-id "$APPLE_ID" --team-id "$TEAM_ID" --keychain-profile "$NOTARYTOOL_PROFILE" --wait 2>&1)
    echo "$NOTARIZE_OUT" | tail -4
    echo "$NOTARIZE_OUT" | grep -q "status: Accepted" || fail "Notarization NOT accepted — aborting before publish. Check the Apple notary log above."
    xcrun stapler staple "$DMG_PATH" && xcrun stapler validate "$DMG_PATH" && echo "  ✓ stapled" || fail "Stapling failed"
else
    echo "  (notarization skipped — DMG is signed but not notarized/stapled)"
fi

# ── 7. generate_appcast (signed appcast + deltas) — RELIMPR #5 ──
echo ""; echo "→ [7/9] Generating appcast"
mkdir -p "$RELEASES_DIR"
cp "$DMG_PATH" "$RELEASES_DIR/$DMG_NAME"
DOWNLOAD_PREFIX="https://github.com/$GITHUB_REPO/releases/download/v$VERSION/"
# --maximum-versions 0 keeps the FULL version history in the feed (the default
# prunes to ~6 and moves older DMGs to old_updates/, which would shrink the
# appcast on every release).
"$SPARKLE_BIN/generate_appcast" --maximum-versions 0 --download-url-prefix "$DOWNLOAD_PREFIX" -o "$APPCAST_OUT" "$RELEASES_DIR" 2>&1 | tail -2

# generate_appcast applies one --download-url-prefix to every item, but GitHub
# hosts each DMG under its OWN tag. Rewrite each DMG enclosure URL's tag segment
# to the version in its filename so the whole history's links stay correct, not
# just the newest. (Deltas need no rewrite: they're only ever generated for the
# latest update, which is hosted under v$VERSION — exactly the prefix already.)
perl -0pi -e 's{releases/download/v[^/"]+/([^"/]*-([0-9]+\.[0-9]+\.[0-9]+)\.dmg)}{releases/download/v$2/$1}g;' "$APPCAST_OUT"
echo "  → $APPCAST_OUT"

# Delta files for THIS release get uploaded alongside the DMG so Sparkle's
# incremental updates resolve. Sparkle names deltas by BUILD NUMBER as
# "<AppName><newBuild>-<oldBuild>.delta" (e.g. OptaKube800-700.delta), so match
# the current build ($BUILD_NUM) as the "new" side.
DELTAS=()
while IFS= read -r d; do [ -n "$d" ] && DELTAS+=("$d"); done < <(find "$RELEASES_DIR" -maxdepth 1 -name "${APP_NAME}${BUILD_NUM}-*.delta" 2>/dev/null)
[ "${#DELTAS[@]}" -gt 0 ] && echo "  deltas: ${#DELTAS[@]}"

# ── dry-run stops here ──
if [ "$DRY_RUN" = 1 ]; then
    echo ""; echo "→ [8-9/9] SKIPPED (dry run)"
    echo "  DMG:     $DMG_PATH"
    echo "  Appcast: $APPCAST_OUT"
    exit 0
fi

# ── 8. Commit (targeted — RELIMPR #3), tag, push ──
echo ""; echo "→ [8/9] Commit, tag, push"
git add "${VERSION_FILES[@]}" CHANGELOG.md appcast.xml
CHANGELOG_EXCERPT=$(awk "/^## \\[$VERSION\\]/{f=1;next} /^## \\[/{f=0} f" CHANGELOG.md 2>/dev/null || true)
[ -n "$CHANGELOG_EXCERPT" ] || CHANGELOG_EXCERPT="See CHANGELOG.md"
git commit -m "Release v$VERSION"
RELEASE_COMMITTED=1   # disarm the rollback trap — the bump is now recorded
git tag -a "v$VERSION" -m "Release v$VERSION"
git push origin "$GIT_BRANCH"
git push origin "v$VERSION"

# ── 9. GitHub release ──
echo ""; echo "→ [9/9] GitHub release"
# Build the asset list (DMG + any deltas) — guarded for bash 3.2, where
# "${empty[@]}" under set -u is an unbound-variable error.
GH_ASSETS=("$DMG_PATH")
[ "${#DELTAS[@]}" -gt 0 ] && GH_ASSETS+=("${DELTAS[@]}")
gh release create "v$VERSION" "${GH_ASSETS[@]}" --latest \
    --repo "$GITHUB_REPO" \
    --title "OptaKube v$VERSION" \
    --notes "$CHANGELOG_EXCERPT

---
**Download:** [${DMG_NAME}](https://github.com/$GITHUB_REPO/releases/download/v$VERSION/$DMG_NAME)
Signed, notarized, and stapled. Drag to Applications to install.

Made by [Souris.CLOUD](https://bio.souris.cloud) | [Support on Ko-fi](https://ko-fi.com/souriscloud)"

echo ""; echo "=== Release v$VERSION complete ==="
echo "  https://github.com/$GITHUB_REPO/releases/tag/v$VERSION"

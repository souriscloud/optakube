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
# Tighten permissions *before* reading, so a world-readable credentials file is fixed
# rather than being read first and secured afterwards.
chmod 600 "$ENV_FILE" 2>/dev/null || true
# shellcheck source=scripts/.env
source "$ENV_FILE"
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
# The app and DMG are still codesigned in this mode — generate_appcast requires a signed
# app — only Apple's notarization round-trip and stapling are skipped.
[ "$SKIP_NOTARIZE" = 1 ] && echo "*** SKIP-NOTARIZE — still codesigned, but not notarized or stapled ***"

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
    # Use the exit code as the signal, and the message text only to classify the failure.
    # Grepping for the word "error" was the sole check, so any auth problem phrased
    # without it ("Unauthorized", "No submissions found") sailed through preflight and
    # surfaced 20 minutes later at the notarization step — and conversely a benign history
    # row containing "error" aborted a perfectly good release.
    NOTARY_STATUS=0
    NOTARY_OUT=$(xcrun notarytool history --keychain-profile "$NOTARYTOOL_PROFILE" 2>&1) || NOTARY_STATUS=$?
    if [ "$NOTARY_STATUS" -ne 0 ]; then
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

# The Keychain must hold *the* key, not just any key. generate_appcast re-signs the
# ENTIRE version history on every run, so signing once with the wrong key invalidates
# every item in the feed at once: every installed copy rejects the signature and
# auto-update is dead permanently, with no way to push a fix. The key is shared across
# souris.cloud apps, which makes a mismatch realistic (new laptop, restored Keychain,
# a sibling app's key).
KEYCHAIN_PUBKEY=$("$SPARKLE_BIN/generate_keys" -p 2>/dev/null | tr -d '[:space:]')
PLIST_PUBKEY=$(plutil -extract SUPublicEDKey raw "Sources/OptaKube/Info.plist" 2>/dev/null | tr -d '[:space:]')
[ -n "$KEYCHAIN_PUBKEY" ] || fail "Could not read the Sparkle public key from the Keychain."
[ -n "$PLIST_PUBKEY" ] || fail "SUPublicEDKey missing from Info.plist."
if [ "$KEYCHAIN_PUBKEY" != "$PLIST_PUBKEY" ]; then
    echo "  Keychain: $KEYCHAIN_PUBKEY" >&2
    echo "  Info.plist: $PLIST_PUBKEY" >&2
    fail "Keychain EdDSA key does not match SUPublicEDKey — signing with it would break auto-update for EVERY existing user."
fi

# generate_appcast rebuilds the feed from whatever DMGs are in $RELEASES_DIR, and that
# directory is gitignored. Running from a fresh clone would therefore regenerate a
# ONE-item appcast and commit it, silently destroying the published version history.
if [ "$DRY_RUN" = 0 ] && [ -f "$ROOT_DIR/appcast.xml" ]; then
    COMMITTED_ITEMS=$(grep -c '<item>' "$ROOT_DIR/appcast.xml" || echo 0)
    LOCAL_DMGS=$(find "$ROOT_DIR/releases" -maxdepth 1 -name '*.dmg' 2>/dev/null | wc -l | tr -d ' ')
    if [ "$LOCAL_DMGS" -lt "$COMMITTED_ITEMS" ]; then
        echo "  appcast has $COMMITTED_ITEMS items but releases/ holds only $LOCAL_DMGS DMG(s)." >&2
        fail "Regenerating now would shrink the published feed and strand users on older versions. Restore the release DMGs to releases/ first (download them from the GitHub releases page)."
    fi
fi

# The appcast is served from a branch, so committing on one branch while pushing another
# publishes nothing — the tag and release would go out with a feed no user ever sees.
if [ "$DRY_RUN" = 0 ]; then
    CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
    [ "$CURRENT_BRANCH" = "$GIT_BRANCH" ] \
        || fail "On branch '$CURRENT_BRANCH' but releases publish from '$GIT_BRANCH'. Switch first."
    git fetch origin "$GIT_BRANCH" >/dev/null 2>&1 || true
    git merge-base --is-ancestor "origin/$GIT_BRANCH" HEAD 2>/dev/null \
        || fail "Local $GIT_BRANCH is behind origin/$GIT_BRANCH — the push would be rejected after the version bump was already committed. Pull first."
fi

# A release must advance the build number, or Sparkle never offers it to anyone.
COMMITTED_BUILD=$(git show "HEAD:Sources/OptaKube/Info.plist" 2>/dev/null \
    | python3 -c "import re,sys; m=re.search(r'<key>CFBundleVersion</key>\s*<string>(\d+)</string>', sys.stdin.read()); print(m.group(1) if m else 0)" 2>/dev/null || echo 0)
NEW_BUILD=$(python3 -c "
major, minor, patch = (int(x) for x in '$VERSION'.split('.'))
print(major * 10000 + minor * 100 + patch)")
if [ "$DRY_RUN" = 0 ] && [ "$NEW_BUILD" -le "$COMMITTED_BUILD" ]; then
    fail "Build $NEW_BUILD (v$VERSION) is not newer than the committed build $COMMITTED_BUILD. Sparkle compares these, so no existing user would be offered this release."
fi

echo "  Running tests…"
# Rely on swift test's exit code (piping to grep would mask it; the swift-testing
# runner prints "passed" for its 0 tests even when XCTest cases fail).
TEST_LOG=$(mktemp -t optakube-test)
if swift test >"$TEST_LOG" 2>&1; then
    echo "  ✓ tests passed"
else
    tail -20 "$TEST_LOG"
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
VERSION_FILES=("Sources/OptaKube/Views/Settings/AboutView.swift" "Sources/OptaKube/Info.plist")

# Snapshot the files this script rewrites, so an abort restores exactly what was there.
# The trap used to `git checkout --` them, which in --dry-run (where a dirty tree is
# allowed, and which RELEASE-GUIDE explicitly recommends rehearsing on) silently
# discarded the user's uncommitted edits to those files.
BACKUP_DIR="$(mktemp -d -t optakube-release-backup)"
for f in "${VERSION_FILES[@]}" "appcast.xml"; do
    [ -f "$f" ] && cp "$f" "$BACKUP_DIR/$(basename "$f")"
done
RELEASE_COMMITTED=0
revert_on_abort() {
    [ "$RELEASE_COMMITTED" = 1 ] && { rm -rf "$BACKUP_DIR"; return; }
    local restored=0
    # appcast.xml is included deliberately: generate_appcast overwrites it before the
    # commit, so an abort in between used to leave the working tree advertising a version
    # that was never released — and the next run then died on the dirty-tree check,
    # inviting the operator to commit that inconsistent state.
    for f in "${VERSION_FILES[@]}" "appcast.xml"; do
        if [ -f "$BACKUP_DIR/$(basename "$f")" ]; then
            cp "$BACKUP_DIR/$(basename "$f")" "$f" && restored=1
        fi
    done
    [ "$restored" = 1 ] && echo "Reverted version bump and appcast (release aborted before commit)." >&2
    rm -rf "$BACKUP_DIR"
}
trap revert_on_abort EXIT

# re.subn + an exact count assertion. Plain re.sub silently matched nothing if a file was
# ever reformatted, so the files were rewritten UNCHANGED while the script reported
# success — shipping a DMG named for the new version containing the old bundle version,
# which produces a duplicate sparkle:version and an update no existing user is offered.
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
    for pat, rep in subs:
        s, n = re.subn(pat, rep, s)
        if n != 1:
            sys.exit(f'  ERROR: pattern matched {n} times (expected 1) in {path}: {pat}')
    open(path, 'w').write(s)
print(f'  v{v} (build {build})')
PY

BUILD_NUM=$(plutil -extract CFBundleVersion raw "Sources/OptaKube/Info.plist")
PLIST_SHORT=$(plutil -extract CFBundleShortVersionString raw "Sources/OptaKube/Info.plist")
ABOUT_VERSION=$(sed -n 's/^[[:space:]]*static let version = "\([^"]*\)".*/\1/p' \
    "Sources/OptaKube/Views/Settings/AboutView.swift" | head -1)
[ "$PLIST_SHORT" = "$VERSION" ] || fail "CFBundleShortVersionString is '$PLIST_SHORT', expected '$VERSION'."
[ "$BUILD_NUM" = "$NEW_BUILD" ] || fail "CFBundleVersion is '$BUILD_NUM', expected '$NEW_BUILD'."
[ "$ABOUT_VERSION" = "$VERSION" ] || fail "AppInfo.version is '$ABOUT_VERSION', expected '$VERSION'."
echo "  ✓ version files verified"

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
[ -f "Sources/OptaKube/Resources/AppIcon.icns" ] \
    || fail "AppIcon.icns is missing — the release would ship without an icon."
cp "Sources/OptaKube/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/"
[ -d "$ROOT_DIR/.build/release/OptaKube_OptaKube.bundle" ] && cp -R "$ROOT_DIR/.build/release/OptaKube_OptaKube.bundle" "$APP_DIR/Contents/Resources/"

# If neither path resolves, the loop used to end silently, install_name_tool's failure was
# swallowed by `|| true`, codesign --verify passed (it doesn't resolve @rpath) and
# notarization passed (Apple never launches the app) — shipping a DMG that dies at launch
# with "Library not loaded: @rpath/Sparkle.framework" for 100% of users.
SPARKLE_FW_COPIED=0
for fw in "$ROOT_DIR/.build/arm64-apple-macosx/release/Sparkle.framework" \
          "$ROOT_DIR/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"; do
    [ -d "$fw" ] && { cp -R "$fw" "$APP_DIR/Contents/Frameworks/"; SPARKLE_FW_COPIED=1; break; }
done
[ "$SPARKLE_FW_COPIED" = 1 ] \
    || fail "Sparkle.framework not found in .build — the app would crash on launch. Run 'swift build -c release' and check Sparkle's artifact layout."
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP_DIR/Contents/MacOS/$APP_NAME" \
    || fail "Could not add the @rpath entry for Sparkle.framework."

# Prove the dynamic linker can actually resolve everything, which codesign does not check.
if otool -L "$APP_DIR/Contents/MacOS/$APP_NAME" | grep -q "@rpath/Sparkle.framework"; then
    [ -f "$APP_DIR/Contents/Frameworks/Sparkle.framework/Versions/A/Sparkle" ] \
        || [ -f "$APP_DIR/Contents/Frameworks/Sparkle.framework/Sparkle" ] \
        || fail "The binary links @rpath/Sparkle.framework but no Sparkle binary was bundled."
fi

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
# A leftover volume from an earlier failed run makes macOS mount this one as
# "/Volumes/OptaKube 1", while the AppleScript below addresses disk "OptaKube" — so it
# would style the stale volume and leave this DMG unstyled.
[ -d "/Volumes/$APP_NAME" ] \
    && fail "/Volumes/$APP_NAME is already mounted from an earlier run. Eject it and retry."
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
    # Converting a still-attached read-write image can produce an inconsistent DMG that
    # nonetheless signs, notarizes and staples cleanly. Detaching must actually succeed.
    sync
    DETACHED=0
    for attempt in 1 2 3; do
        if hdiutil detach "$MOUNT_DIR" >/dev/null 2>&1; then DETACHED=1; break; fi
        sleep 2
        if hdiutil detach "$MOUNT_DIR" -force >/dev/null 2>&1; then DETACHED=1; break; fi
    done
    [ "$DETACHED" = 1 ] || fail "Could not detach $MOUNT_DIR — refusing to convert a mounted image."
}
hdiutil convert "$DMG_TEMP" -format UDZO -imagekey zlib-level=9 -o "$DMG_PATH" 2>/dev/null
hdiutil verify "$DMG_PATH" >/dev/null 2>&1 || fail "The built DMG failed hdiutil verify."
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
    # What a clean machine actually does when the user opens the download. `codesign
    # --verify` does not answer this — it checks the signature, not Gatekeeper policy.
    if spctl --assess --type open --context context:primary-signature -v "$DMG_PATH" 2>&1 | grep -q "accepted"; then
        echo "  ✓ Gatekeeper accepts the DMG"
    else
        spctl --assess --type open --context context:primary-signature -vv "$DMG_PATH" 2>&1 | tail -5 >&2
        fail "Gatekeeper would reject this DMG on a clean machine."
    fi
else
    echo "  (notarization skipped — DMG is signed but not notarized/stapled)"
fi

# ── 7. generate_appcast (signed appcast + deltas) — RELIMPR #5 ──
echo ""; echo "→ [7/9] Generating appcast"
mkdir -p "$RELEASES_DIR"
cp "$DMG_PATH" "$RELEASES_DIR/$DMG_NAME"
DOWNLOAD_PREFIX="https://github.com/$GITHUB_REPO/releases/download/v$VERSION/"

# Release notes for the update dialog. generate_appcast picks up releases/<version>.html
# automatically; without it every user saw "A new version is available" above a blank
# notes pane, for an app whose CHANGELOG is genuinely good.
CHANGELOG_EXCERPT=$(awk "/^## \\[$VERSION\\]/{f=1;next} /^## \\[/{f=0} f" CHANGELOG.md 2>/dev/null || true)
[ -n "$CHANGELOG_EXCERPT" ] || CHANGELOG_EXCERPT="See CHANGELOG.md"
python3 - "$VERSION" "$RELEASES_DIR" <<'PY'
import html, os, re, sys
version, releases_dir = sys.argv[1], sys.argv[2]
text = ""
with open("CHANGELOG.md") as fh:
    capturing = False
    for line in fh:
        if re.match(r"^## \[" + re.escape(version) + r"\]", line):
            capturing = True
            continue
        if capturing and line.startswith("## ["):
            break
        if capturing:
            text += line
body = []
for line in text.splitlines():
    stripped = line.strip()
    if not stripped:
        continue
    if stripped.startswith("### "):
        body.append(f"<h3>{html.escape(stripped[4:])}</h3>")
    elif stripped.startswith("- "):
        # Render **bold** since the changelog leans on it heavily.
        item = html.escape(stripped[2:])
        item = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", item)
        body.append(f"<li>{item}</li>")
    else:
        body.append(f"<p>{html.escape(stripped)}</p>")
# Wrap consecutive <li> runs in a list.
out, in_list = [], False
for chunk in body:
    if chunk.startswith("<li>") and not in_list:
        out.append("<ul>"); in_list = True
    elif not chunk.startswith("<li>") and in_list:
        out.append("</ul>"); in_list = False
    out.append(chunk)
if in_list:
    out.append("</ul>")
os.makedirs(releases_dir, exist_ok=True)
path = os.path.join(releases_dir, f"{version}.html")
with open(path, "w") as fh:
    fh.write('<meta charset="utf-8"><style>body{font:13px -apple-system,sans-serif;'
             'margin:12px;line-height:1.5}h3{font-size:13px;margin:12px 0 4px}'
             'ul{margin:4px 0;padding-left:18px}</style>\n')
    fh.write("\n".join(out) or f"<p>See CHANGELOG.md for v{version}.</p>")
print(f"  release notes → {path}")
PY
# --maximum-versions 0 keeps the FULL version history in the feed (the default
# prunes to ~6 and moves older DMGs to old_updates/, which would shrink the
# appcast on every release).
"$SPARKLE_BIN/generate_appcast" --maximum-versions 0 --download-url-prefix "$DOWNLOAD_PREFIX" -o "$APPCAST_OUT" "$RELEASES_DIR" 2>&1 | tail -2

# generate_appcast applies one --download-url-prefix to every item, but GitHub
# hosts each DMG under its OWN tag. Rewrite each DMG enclosure URL's tag segment
# to the version in its filename so the whole history's links stay correct, not
# just the newest.
perl -0pi -e 's{releases/download/v[^/"]+/([^"/]*-([0-9]+\.[0-9]+\.[0-9]+)\.dmg)}{releases/download/v$2/$1}g;' "$APPCAST_OUT"

# Deltas need the same treatment from the second delta-bearing release onward. The
# earlier assumption that they only ever belong to the newest item holds for exactly one
# release: generate_appcast caches .delta files in releases/ and reuses them, so older
# items keep their deltas and would have this run's tag stamped on them. Only deltas
# whose new-side build is $BUILD_NUM are uploaded under v$VERSION, so the rest 404 and
# Sparkle silently falls back to the full download. Map each delta's new-side build back
# to its version and rewrite the tag accordingly.
python3 - "$APPCAST_OUT" "$APP_NAME" <<'PY'
import re, sys
path, app = sys.argv[1], sys.argv[2]
xml = open(path).read()

# Build number -> short version, from the items themselves.
builds = {}
for item in re.findall(r"<item>.*?</item>", xml, re.S):
    b = re.search(r"<sparkle:version>(\d+)</sparkle:version>", item)
    v = re.search(r"<sparkle:shortVersionString>([^<]+)</sparkle:shortVersionString>", item)
    if b and v:
        builds[b.group(1)] = v.group(1)

def fix(match):
    url, filename, new_build = match.group(0), match.group(1), match.group(2)
    version = builds.get(new_build)
    if not version:
        return url
    return re.sub(r"releases/download/v[^/\"]+/", f"releases/download/v{version}/", url)

pattern = r"releases/download/v[^/\"]+/(" + re.escape(app) + r"(\d+)-\d+\.delta)"
fixed, count = re.subn(pattern, fix, xml)
if count:
    open(path, "w").write(fixed)
print(f"  delta URLs checked ({count} rewritten)")
PY

echo "  → $APPCAST_OUT"

# Verify what we are about to publish. Nothing checked the generated appcast at all: not
# that it parsed, not that its newest item matched the version being released, not that
# the enclosures were signed. An error here disables auto-update for every existing
# install at once, and the repo *is* the feed, so the mistake publishes immediately.
if [ -f "$ROOT_DIR/.github/scripts/check_appcast.py" ] && [ "$DRY_RUN" = 0 ]; then
    python3 "$ROOT_DIR/.github/scripts/check_appcast.py" || fail "Generated appcast failed validation — refusing to publish."
else
    python3 -c "
import sys, xml.etree.ElementTree as ET
try:
    ET.parse('$APPCAST_OUT')
except ET.ParseError as e:
    sys.exit(f'appcast is not well-formed: {e}')
" || fail "Generated appcast is not well-formed XML."
fi

# The DMG's recorded length must match the file, or Sparkle rejects the download.
DMG_BYTES=$(stat -f%z "$DMG_PATH")
grep -q "length=\"$DMG_BYTES\"" "$APPCAST_OUT" \
    || fail "No enclosure in the appcast records length $DMG_BYTES for $DMG_NAME."
echo "  ✓ appcast verified"

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

# ── 8. Publish the download FIRST ──
#
# Order matters more than anything else in this script. SUFeedURL points at
# appcast.xml on $GIT_BRANCH, so the instant that file is pushed every installed copy
# sees the new version and starts downloading its enclosure URL. Publishing the appcast
# before the asset existed meant, at best, a window of "Update failed" alerts — and if
# `gh release create` then failed (expired token, network, upload timeout, tag already
# present), the repo advertised a 404 download to every user permanently, with the
# rollback trap already disarmed.
#
# So: create the release as a draft, upload the assets, prove the URL resolves, then
# commit and push the appcast, then publish the release.
echo ""; echo "→ [8/9] Uploading release assets (draft)"

# Build the asset list (DMG + any deltas) — guarded for bash 3.2, where
# "${empty[@]}" under set -u is an unbound-variable error.
GH_ASSETS=("$DMG_PATH")
[ "${#DELTAS[@]}" -gt 0 ] && GH_ASSETS+=("${DELTAS[@]}")

RELEASE_NOTES="$CHANGELOG_EXCERPT

---
**Download:** [${DMG_NAME}](https://github.com/$GITHUB_REPO/releases/download/v$VERSION/$DMG_NAME)
Signed, notarized, and stapled. Drag to Applications to install.

Requires macOS 14 (Sonoma) or later on Apple Silicon.

Made by [Souris.CLOUD](https://bio.souris.cloud) | [Support on Ko-fi](https://ko-fi.com/souriscloud)"

# The tag has to exist for the release to hang off, but pushing the branch (and with it
# the appcast) is deliberately left until after the assets are verified.
git add "${VERSION_FILES[@]}" CHANGELOG.md appcast.xml
git commit -m "Release v$VERSION"
RELEASE_COMMITTED=1   # disarm the rollback trap — the bump is now recorded
git tag -a "v$VERSION" -m "Release v$VERSION"
git push origin "v$VERSION"

gh release create "v$VERSION" "${GH_ASSETS[@]}" --draft \
    --repo "$GITHUB_REPO" \
    --title "OptaKube v$VERSION" \
    --notes "$RELEASE_NOTES" \
    || fail "Could not create the draft release. Nothing has been published; the appcast is still unpushed. Delete the tag with 'git push --delete origin v$VERSION && git tag -d v$VERSION' before retrying."

echo "  ✓ draft release created with ${#GH_ASSETS[@]} asset(s)"

# ── 9. Verify the download, then publish the feed ──
echo ""; echo "→ [9/9] Verifying download, publishing"

# A draft release's assets are not yet reachable at the public download URL, so publish
# the release first and *then* check the URL — before the appcast, which is what users'
# Sparkle actually reads.
gh release edit "v$VERSION" --repo "$GITHUB_REPO" --draft=false --latest \
    || fail "Could not publish the release. The appcast is still unpushed, so no user has been offered a broken update."

DOWNLOAD_URL="https://github.com/$GITHUB_REPO/releases/download/v$VERSION/$DMG_NAME"
DOWNLOAD_OK=0
for attempt in 1 2 3 4 5; do
    if curl -fsIL --max-time 30 "$DOWNLOAD_URL" >/dev/null 2>&1; then DOWNLOAD_OK=1; break; fi
    sleep 3
done
[ "$DOWNLOAD_OK" = 1 ] \
    || fail "The published DMG is not reachable at $DOWNLOAD_URL — refusing to push the appcast, so existing users are not offered a broken update. Fix the release assets, then push $GIT_BRANCH manually."
echo "  ✓ $DMG_NAME is downloadable"

# Only now does the feed go live for every installed copy.
git push origin "$GIT_BRANCH" \
    || fail "The release is published but the appcast push failed. Existing users will not see v$VERSION until '$GIT_BRANCH' is pushed. Run: git push origin $GIT_BRANCH"

echo ""; echo "=== Release v$VERSION complete ==="
echo "  https://github.com/$GITHUB_REPO/releases/tag/v$VERSION"

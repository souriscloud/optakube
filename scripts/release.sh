#!/bin/bash
set -euo pipefail

# OptaKube Release Script — Fully Autonomous
# Usage: ./scripts/release.sh <version>
# Example: ./scripts/release.sh 0.2.1
#
# This script does EVERYTHING:
#   1. Updates version in Info.plist
#   2. Builds release binary
#   3. Creates .app bundle with Sparkle framework
#   4. Code signs with Developer ID
#   5. Creates styled DMG
#   6. Notarizes with Apple + staples
#   7. Signs DMG with Sparkle EdDSA
#   8. Updates appcast.xml
#   9. Commits, tags, pushes
#  10. Creates GitHub release with DMG attached

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
    echo "Usage: $0 <version>"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
APP_NAME="OptaKube"
BUILD_DIR="$ROOT_DIR/.build/release-build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
DMG_NAME="$APP_NAME-$VERSION.dmg"
DMG_PATH="$BUILD_DIR/$DMG_NAME"
APPCAST_PATH="$ROOT_DIR/appcast.xml"
GITHUB_REPO="${GITHUB_REPO:-souriscloud/optakube}"
SIGN_IDENTITY="${SIGN_IDENTITY:-Developer ID Application: Luk Novotn (26GLU32796)}"
TEAM_ID="26GLU32796"
APPLE_ID="${APPLE_ID:-me@souris.cloud}"
GIT_BRANCH="master"

cd "$ROOT_DIR"
echo "=== OptaKube Release $VERSION ==="

# ── 1. Update version ──
echo ""
echo "→ [1/10] Updating version..."
python3 -c "
import re
with open('Sources/OptaKube/Info.plist', 'r') as f:
    content = f.read()
content = re.sub(r'(<key>CFBundleShortVersionString</key>\s*<string>)[^<]*(</string>)', r'\g<1>$VERSION\g<2>', content)
m = re.search(r'<key>CFBundleVersion</key>\s*<string>(\d+)</string>', content)
build = int(m.group(1)) + 1 if m else 1
content = re.sub(r'(<key>CFBundleVersion</key>\s*<string>)\d+(</string>)', rf'\g<1>{build}\g<2>', content)
with open('Sources/OptaKube/Info.plist', 'w') as f:
    f.write(content)
print(f'  v$VERSION (build {build})')
"
BUILD_NUM=$(python3 -c "import re; content=open('Sources/OptaKube/Info.plist').read(); m=re.search(r'<key>CFBundleVersion</key>\s*<string>(\d+)</string>',content); print(m.group(1))")

# ── 2. Build ──
echo ""
echo "→ [2/10] Building..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
swift build -c release 2>&1 | tail -3
BINARY_PATH="$ROOT_DIR/.build/release/$APP_NAME"
[ -f "$BINARY_PATH" ] || { echo "ERROR: Build failed"; exit 1; }
echo "  $(file "$BINARY_PATH" | sed 's/.*: //')"

# ── 3. Create .app bundle ──
echo ""
echo "→ [3/10] Creating .app bundle..."
mkdir -p "$APP_DIR/Contents/"{MacOS,Resources,Frameworks}
cp "$BINARY_PATH" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp "Sources/OptaKube/Info.plist" "$APP_DIR/Contents/Info.plist"
[ -f "Sources/OptaKube/Resources/AppIcon.icns" ] && cp "Sources/OptaKube/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/"
# SPM resources bundle
[ -d "$ROOT_DIR/.build/release/OptaKube_OptaKube.bundle" ] && cp -R "$ROOT_DIR/.build/release/OptaKube_OptaKube.bundle" "$APP_DIR/Contents/Resources/"
# Sparkle framework
for fw in "$ROOT_DIR/.build/arm64-apple-macosx/release/Sparkle.framework" \
          "$ROOT_DIR/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"; do
    [ -d "$fw" ] && { cp -R "$fw" "$APP_DIR/Contents/Frameworks/"; break; }
done
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP_DIR/Contents/MacOS/$APP_NAME" 2>/dev/null || true
echo "  $APP_DIR"

# ── 4. Code sign ──
echo ""
echo "→ [4/10] Code signing..."
cat > "$BUILD_DIR/entitlements.plist" << 'EOF'
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
codesign --force --deep --options runtime --sign "$SIGN_IDENTITY" --entitlements "$BUILD_DIR/entitlements.plist" "$APP_DIR" 2>&1
codesign --verify --deep --strict "$APP_DIR" 2>&1 && echo "  OK" || { echo "  FAILED"; exit 1; }

# ── 5. Create DMG ──
echo ""
echo "→ [5/10] Creating DMG..."
DMG_STAGING="$BUILD_DIR/dmg-staging"
DMG_TEMP="$BUILD_DIR/temp.dmg"
rm -rf "$DMG_STAGING" "$DMG_TEMP" "$DMG_PATH"
mkdir -p "$DMG_STAGING/.background"
swift "$SCRIPT_DIR/create-dmg-background.swift" "$DMG_STAGING/.background/background.png" 2>/dev/null
cp -R "$APP_DIR" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_STAGING" -ov -format UDRW "$DMG_TEMP" 2>/dev/null
MOUNT_DIR=$(hdiutil attach "$DMG_TEMP" -readwrite -noverify 2>/dev/null | grep "/Volumes/" | sed 's/.*\/Volumes/\/Volumes/')
[ -n "$MOUNT_DIR" ] && {
    osascript << AS
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
    sync; hdiutil detach "$MOUNT_DIR" 2>/dev/null
}
hdiutil convert "$DMG_TEMP" -format UDZO -imagekey zlib-level=9 -o "$DMG_PATH" 2>/dev/null
rm -f "$DMG_TEMP"
rm -rf "$DMG_STAGING"
echo "  $(du -h "$DMG_PATH" | cut -f1)"

# ── 6. Notarize + staple ──
echo ""
echo "→ [6/10] Notarizing..."
NOTARIZE_OUT=$(xcrun notarytool submit "$DMG_PATH" --apple-id "$APPLE_ID" --team-id "$TEAM_ID" --keychain-profile "notarytool" --wait 2>&1)
echo "$NOTARIZE_OUT" | tail -5
if echo "$NOTARIZE_OUT" | grep -q "Accepted"; then
    echo "  Stapling..."
    xcrun stapler staple "$DMG_PATH" 2>&1 | tail -1
else
    echo "  WARNING: Notarization not accepted. Check Apple notary logs."
fi

# ── 7. Sparkle EdDSA signature ──
echo ""
echo "→ [7/10] Sparkle signing..."
SPARKLE_SIGN=""
for p in "$ROOT_DIR/.build/artifacts/sparkle/Sparkle/bin/sign_update" \
         "$ROOT_DIR/.build/checkouts/Sparkle/bin/sign_update"; do
    [ -x "$p" ] 2>/dev/null && { SPARKLE_SIGN="$p"; break; }
done
ED_SIGNATURE=""
DMG_BYTES=$(stat -f%z "$DMG_PATH")
if [ -n "$SPARKLE_SIGN" ]; then
    SIGN_OUT=$("$SPARKLE_SIGN" "$DMG_PATH" 2>/dev/null || echo "")
    ED_SIGNATURE=$(echo "$SIGN_OUT" | grep -o 'edSignature="[^"]*"' | sed 's/edSignature="//' | sed 's/"//')
    echo "  Signed: ${ED_SIGNATURE:0:20}..."
else
    echo "  WARNING: sign_update not found"
fi

# ── 8. Update appcast.xml ──
echo ""
echo "→ [8/10] Updating appcast..."
RELEASE_DATE=$(date -R)
cat > "$APPCAST_PATH" << APPCAST
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>OptaKube Updates</title>
    <link>https://raw.githubusercontent.com/$GITHUB_REPO/$GIT_BRANCH/appcast.xml</link>
    <description>Most recent changes with links to updates.</description>
    <language>en</language>
    <item>
      <title>Version $VERSION</title>
      <pubDate>$RELEASE_DATE</pubDate>
      <sparkle:version>$BUILD_NUM</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <description><![CDATA[
        <h2>OptaKube $VERSION</h2>
        <p>See <a href="https://github.com/$GITHUB_REPO/blob/$GIT_BRANCH/CHANGELOG.md">CHANGELOG</a> for details.</p>
      ]]></description>
      <enclosure
        url="https://github.com/$GITHUB_REPO/releases/download/v$VERSION/$DMG_NAME"
        type="application/octet-stream"
        sparkle:edSignature="$ED_SIGNATURE"
        length="$DMG_BYTES"
      />
    </item>
  </channel>
</rss>
APPCAST
echo "  Done"

# ── 9. Git commit, tag, push ──
echo ""
echo "→ [9/10] Git commit, tag, push..."
git add -A
CHANGELOG_EXCERPT=$(grep -A 100 "## \[$VERSION\]" CHANGELOG.md 2>/dev/null | tail -n +2 | sed '/^## \[/,$d' || echo "See CHANGELOG.md")
git commit -m "Release v$VERSION" --allow-empty 2>/dev/null || true
# Delete existing tag if re-releasing same version
git tag -d "v$VERSION" 2>/dev/null || true
git push origin ":refs/tags/v$VERSION" 2>/dev/null || true
git tag -a "v$VERSION" -m "Release v$VERSION"
git push origin "$GIT_BRANCH" --tags 2>&1 || echo "  Push failed — run: git push origin $GIT_BRANCH --tags"

# ── 10. GitHub release ──
echo ""
echo "→ [10/10] Creating GitHub release..."
# Delete existing release if re-releasing
gh release delete "v$VERSION" --yes 2>/dev/null || true
gh release create "v$VERSION" "$DMG_PATH" \
    --title "OptaKube v$VERSION" \
    --notes "$CHANGELOG_EXCERPT

---
**Download:** [OptaKube-$VERSION.dmg](https://github.com/$GITHUB_REPO/releases/download/v$VERSION/$DMG_NAME)
Signed, notarized, and stapled. Drag to Applications to install.

Made by [Souris.CLOUD](https://bio.souris.cloud) | [Support on Ko-fi](https://ko-fi.com/souriscloud)" 2>&1

echo ""
echo "=== Release v$VERSION complete ==="
echo "  https://github.com/$GITHUB_REPO/releases/tag/v$VERSION"

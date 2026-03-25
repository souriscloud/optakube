#!/bin/bash
set -euo pipefail

# OptaKube Release Script
# Usage: ./scripts/release.sh <version>
# Example: ./scripts/release.sh 0.2.0
#
# Prerequisites:
#   - Sparkle's generate_keys has been run once (creates EdDSA keypair)
#   - gh CLI installed and authenticated (for GitHub releases)
#   - SPARKLE_KEY env var or ~/Library/Sparkle/ed25519 key exists
#
# What this script does:
#   1. Updates version in Info.plist and AppInfo
#   2. Builds universal binary (arm64 + x86_64)
#   3. Creates .app bundle
#   4. Signs with Sparkle EdDSA key
#   5. Creates DMG
#   6. Updates appcast.xml
#   7. Commits, tags, pushes
#   8. Creates GitHub release with DMG attached

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
    echo "Usage: $0 <version>"
    echo "Example: $0 0.2.0"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
APP_NAME="OptaKube"
BUNDLE_ID="cloud.souris.optakube"
BUILD_DIR="$ROOT_DIR/.build/release-build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
DMG_NAME="$APP_NAME-$VERSION.dmg"
DMG_PATH="$BUILD_DIR/$DMG_NAME"
APPCAST_PATH="$ROOT_DIR/appcast.xml"

# GitHub repo (update this)
GITHUB_REPO="${GITHUB_REPO:-souriscloud/optakube}"
DOWNLOAD_BASE="https://github.com/$GITHUB_REPO/releases/download/v$VERSION"

echo "=== OptaKube Release $VERSION ==="
echo ""

# 1. Update version numbers
echo "→ Updating version to $VERSION..."
cd "$ROOT_DIR"

# Update Info.plist
sed -i '' "s|<string>[0-9]*\.[0-9]*\.[0-9]*</string><!-- CFBundleShortVersionString -->|<string>$VERSION</string><!-- CFBundleShortVersionString -->|" Sources/OptaKube/Info.plist 2>/dev/null || true
# More robust: update the line after CFBundleShortVersionString
python3 -c "
import re
with open('Sources/OptaKube/Info.plist', 'r') as f:
    content = f.read()
content = re.sub(
    r'(<key>CFBundleShortVersionString</key>\s*<string>)[^<]*(</string>)',
    r'\g<1>$VERSION\g<2>',
    content
)
# Increment build number
import re as re2
m = re2.search(r'<key>CFBundleVersion</key>\s*<string>(\d+)</string>', content)
if m:
    build = int(m.group(1)) + 1
    content = re2.sub(
        r'(<key>CFBundleVersion</key>\s*<string>)\d+(</string>)',
        rf'\g<1>{build}\g<2>',
        content
    )
with open('Sources/OptaKube/Info.plist', 'w') as f:
    f.write(content)
print(f'  Info.plist: {\"$VERSION\"} (build {build})')
"

# Update AppInfo.swift
sed -i '' "s|static let version = \"[^\"]*\"|static let version = \"$VERSION\"|" Sources/OptaKube/Views/Settings/AboutView.swift
echo "  AppInfo.swift updated"

# 2. Build universal binary
echo ""
echo "→ Building universal binary..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Build release (native arch — universal requires full Xcode Metal toolchain)
swift build -c release 2>&1 | tail -5
BINARY_PATH="$ROOT_DIR/.build/release/$APP_NAME"

if [ ! -f "$BINARY_PATH" ]; then
    echo "ERROR: Build failed, binary not found"
    exit 1
fi
echo "  Binary: $(file "$BINARY_PATH" | sed 's/.*: //')"

# 3. Create .app bundle
echo ""
echo "→ Creating .app bundle..."
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BINARY_PATH" "$APP_DIR/Contents/MacOS/$APP_NAME"

# Copy Info.plist
cp "Sources/OptaKube/Info.plist" "$APP_DIR/Contents/Info.plist"

# Copy icon
if [ -f "Sources/OptaKube/Resources/AppIcon.icns" ]; then
    cp "Sources/OptaKube/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/"
fi

# Copy SPM resources bundle if it exists
RESOURCE_BUNDLE="$ROOT_DIR/.build/release/OptaKube_OptaKube.bundle"
if [ -d "$RESOURCE_BUNDLE" ]; then
    cp -R "$RESOURCE_BUNDLE" "$APP_DIR/Contents/Resources/"
fi

echo "  Bundle: $APP_DIR"

# 3b. Code sign with Developer ID + notarize
echo ""
echo "→ Code signing..."
SIGN_IDENTITY="${SIGN_IDENTITY:-Developer ID Application: Luk Novotn (26GLU32796)}"
TEAM_ID="26GLU32796"
BUNDLE_ID="cloud.souris.optakube"

# Entitlements
cat > "$BUILD_DIR/entitlements.plist" << 'ENTITLEMENTS'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.network.client</key>
    <true/>
    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>
    <key>com.apple.security.cs.allow-unsigned-executable-memory</key>
    <true/>
</dict>
</plist>
ENTITLEMENTS

# Sign all frameworks/dylibs first (deep), then the app
codesign --force --deep --options runtime --sign "$SIGN_IDENTITY" --entitlements "$BUILD_DIR/entitlements.plist" "$APP_DIR" 2>&1
echo "  Signed: $SIGN_IDENTITY"

# Verify
codesign --verify --deep --strict "$APP_DIR" 2>&1 && echo "  Verification: OK" || echo "  Verification: FAILED"

# 4. Sign with Sparkle EdDSA
echo ""
echo "→ Signing for Sparkle..."
SPARKLE_SIGN=""
# Try to find Sparkle's sign_update tool
for signpath in \
    "$ROOT_DIR/.build/artifacts/sparkle/Sparkle/bin/sign_update" \
    "$ROOT_DIR/.build/checkouts/Sparkle/bin/sign_update" \
    "$(which sign_update 2>/dev/null)"; do
    if [ -x "$signpath" 2>/dev/null ]; then
        SPARKLE_SIGN="$signpath"
        break
    fi
done

# 5. Create styled DMG
echo ""
echo "→ Creating DMG..."
DMG_STAGING="$BUILD_DIR/dmg-staging"
DMG_TEMP="$BUILD_DIR/$APP_NAME-temp.dmg"
rm -rf "$DMG_STAGING" "$DMG_TEMP" "$DMG_PATH"
mkdir -p "$DMG_STAGING/.background"

# Generate background image
swift "$SCRIPT_DIR/create-dmg-background.swift" "$DMG_STAGING/.background/background.png" 2>/dev/null

# Copy app and create Applications symlink
cp -R "$APP_DIR" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

# Create a read-write DMG first so we can style it
hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_STAGING" -ov -format UDRW "$DMG_TEMP" 2>/dev/null

# Mount and style with AppleScript
MOUNT_DIR=$(hdiutil attach "$DMG_TEMP" -readwrite -noverify 2>/dev/null | grep "/Volumes/" | sed 's/.*\/Volumes/\/Volumes/')
if [ -n "$MOUNT_DIR" ]; then
    osascript << APPLESCRIPT
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
APPLESCRIPT
    sync
    hdiutil detach "$MOUNT_DIR" 2>/dev/null
fi

# Convert to compressed read-only DMG
hdiutil convert "$DMG_TEMP" -format UDZO -imagekey zlib-level=9 -o "$DMG_PATH" 2>/dev/null
rm -f "$DMG_TEMP"
rm -rf "$DMG_STAGING"

DMG_SIZE=$(du -h "$DMG_PATH" | cut -f1)
echo "  DMG: $DMG_PATH ($DMG_SIZE)"

# 5b. Notarize the DMG
echo ""
echo "→ Notarizing..."
APPLE_ID="${APPLE_ID:-me@souris.cloud}"
if xcrun notarytool submit "$DMG_PATH" --apple-id "$APPLE_ID" --team-id "$TEAM_ID" --keychain-profile "notarytool" --wait 2>&1 | tee /dev/stderr | grep -q "Accepted"; then
    echo "  Notarization: Accepted"
    xcrun stapler staple "$DMG_PATH" 2>&1
    echo "  Stapled"
else
    echo "  WARNING: Notarization failed or keychain profile not set."
    echo "  To set up: xcrun notarytool store-credentials notarytool --apple-id $APPLE_ID --team-id $TEAM_ID"
    echo "  Then re-run this script."
fi

# Get EdDSA signature for appcast
SIGNATURE=""
if [ -n "$SPARKLE_SIGN" ]; then
    SIGNATURE=$("$SPARKLE_SIGN" "$DMG_PATH" 2>/dev/null || echo "")
    echo "  Signature: ${SIGNATURE:0:20}..."
else
    echo "  WARNING: sign_update not found, skipping EdDSA signature"
    echo "  Run: swift package resolve && .build/checkouts/Sparkle/bin/generate_keys"
fi

DMG_BYTES=$(stat -f%z "$DMG_PATH")

# 6. Update appcast.xml
echo ""
echo "→ Updating appcast.xml..."
RELEASE_DATE=$(date -R)

cat > "$APPCAST_PATH" << APPCAST_EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>OptaKube Updates</title>
    <link>https://raw.githubusercontent.com/$GITHUB_REPO/main/appcast.xml</link>
    <description>Most recent changes with links to updates.</description>
    <language>en</language>
    <item>
      <title>Version $VERSION</title>
      <pubDate>$RELEASE_DATE</pubDate>
      <sparkle:version>$DMG_BYTES</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <description><![CDATA[
        <h2>OptaKube $VERSION</h2>
        <p>See <a href="https://github.com/$GITHUB_REPO/blob/main/CHANGELOG.md">CHANGELOG</a> for details.</p>
      ]]></description>
      <enclosure
        url="$DOWNLOAD_BASE/$DMG_NAME"
        type="application/octet-stream"
        sparkle:edSignature="$SIGNATURE"
        length="$DMG_BYTES"
      />
    </item>
  </channel>
</rss>
APPCAST_EOF
echo "  Appcast written to $APPCAST_PATH"

# 7. Git commit, tag, push
echo ""
echo "→ Committing and tagging..."
git add -A
git commit -m "Release v$VERSION

$(grep -A 100 "## \[$VERSION\]" CHANGELOG.md 2>/dev/null | tail -n +2 | sed '/^## \[/,$d' || echo "See CHANGELOG.md")" || echo "  Nothing to commit"

git tag -a "v$VERSION" -m "Release v$VERSION"
echo "  Tagged: v$VERSION"

echo ""
echo "→ Pushing to remote..."
git push origin main --tags 2>/dev/null || echo "  Push failed (no remote configured?). Run: git push origin main --tags"

# 8. Create GitHub release
echo ""
echo "→ Creating GitHub release..."
if command -v gh &>/dev/null; then
    CHANGELOG_BODY=$(grep -A 100 "## \[$VERSION\]" CHANGELOG.md 2>/dev/null | tail -n +2 | sed '/^## \[/,$d' || echo "Release v$VERSION")
    gh release create "v$VERSION" "$DMG_PATH" \
        --title "OptaKube v$VERSION" \
        --notes "$CHANGELOG_BODY" \
        2>/dev/null || echo "  GitHub release failed. Create manually at: https://github.com/$GITHUB_REPO/releases/new"
else
    echo "  gh CLI not found. Install with: brew install gh"
    echo "  Then run: gh release create v$VERSION $DMG_PATH --title 'OptaKube v$VERSION'"
fi

echo ""
echo "=== Release v$VERSION complete ==="
echo ""
echo "Artifacts:"
echo "  DMG: $DMG_PATH"
echo "  Appcast: $APPCAST_PATH"
echo ""
echo "Next steps:"
echo "  1. Verify the DMG works: open $DMG_PATH"
echo "  2. If push failed: git push origin main --tags"
echo "  3. If GH release failed: gh release create v$VERSION $DMG_PATH"
echo "  4. Update SUFeedURL in Info.plist to point to appcast.xml"

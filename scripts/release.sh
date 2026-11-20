#!/usr/bin/env bash
# Build, sign, notarize and publish a Perkle release as a DMG on GitHub.
#
# Usage: scripts/release.sh 1.0 [notes.md]
#
# Needs, once per Mac:
#   - a "Developer ID Application" certificate in the keychain
#   - notarization credentials saved as the "perkle-notary" keychain profile:
#       xcrun notarytool store-credentials perkle-notary --apple-id <email> --team-id <team>
#   - gh, logged in
set -euo pipefail

VERSION="${1:?usage: scripts/release.sh <version> [notes.md]}"
NOTES="${2:-}"
TAG="v$VERSION"
PROFILE="perkle-notary"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/build/release"
DMG="$OUT/Perkle-$VERSION.dmg"

cd "$ROOT"

# Preflight: fail before the slow steps, not after them.
[[ -z "$(git status --porcelain)" ]] || { echo "Working tree is not clean." >&2; exit 1; }
! git rev-parse -q --verify "refs/tags/$TAG" >/dev/null || { echo "Tag $TAG already exists." >&2; exit 1; }
grep -q "MARKETING_VERSION = $VERSION;" Perkle.xcodeproj/project.pbxproj \
    || { echo "MARKETING_VERSION in the project is not $VERSION." >&2; exit 1; }
IDENTITY="$(security find-identity -v -p codesigning | grep -m1 -o '"Developer ID Application: [^"]*"' | tr -d '"')" \
    || { echo "No Developer ID Application certificate found." >&2; exit 1; }
TEAM="$(sed -E 's/.*\(([A-Z0-9]+)\)$/\1/' <<<"$IDENTITY")"
xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null \
    || { echo "Notary profile '$PROFILE' is missing or invalid." >&2; exit 1; }
echo "Signing as: $IDENTITY"

rm -rf "$OUT" && mkdir -p "$OUT"

# 1. Archive and export a Developer ID signed app.
xcodebuild archive -project Perkle.xcodeproj -scheme Perkle -configuration Release \
    -archivePath "$OUT/Perkle.xcarchive" DEVELOPMENT_TEAM="$TEAM" -quiet
cat >"$OUT/export.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>developer-id</string>
    <key>teamID</key><string>$TEAM</string>
    <key>signingStyle</key><string>automatic</string>
</dict>
</plist>
EOF
xcodebuild -exportArchive -archivePath "$OUT/Perkle.xcarchive" \
    -exportOptionsPlist "$OUT/export.plist" -exportPath "$OUT/export" -quiet
APP="$OUT/export/Perkle.app"
codesign --verify --deep --strict "$APP"

# 2. DMG with a drag-to-Applications shortcut.
mkdir -p "$OUT/dmg"
cp -R "$APP" "$OUT/dmg/"
ln -s /Applications "$OUT/dmg/Applications"
hdiutil create -volname "Perkle $VERSION" -srcfolder "$OUT/dmg" -ov -format UDZO "$DMG" >/dev/null
codesign --sign "$IDENTITY" --timestamp "$DMG"

# 3. Notarize and staple, then check Gatekeeper accepts it.
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature --verbose "$DMG"

# 4. Tag and publish.
git tag -a "$TAG" -m "Perkle $VERSION"
git push origin "$TAG"
if [[ -n "$NOTES" ]]; then
    gh release create "$TAG" "$DMG" --title "Perkle $VERSION" --notes-file "$NOTES"
else
    gh release create "$TAG" "$DMG" --title "Perkle $VERSION" --generate-notes
fi
echo "Released $TAG: $(gh release view "$TAG" --json url -q .url)"

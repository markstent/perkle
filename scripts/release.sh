#!/usr/bin/env bash
# Build, sign, notarize and publish a Perkle release as a DMG on GitHub.
#
# Usage: scripts/release.sh 1.0 [notes.md]
#
# Signing and notarization go through the Apple account signed in to Xcode
# (Xcode > Settings > Accounts), using Apple's cloud-managed Developer ID
# certificate, so no certificate or password needs to be on this Mac.
# Also needs gh, logged in.
set -euo pipefail

VERSION="${1:?usage: scripts/release.sh <version> [notes.md]}"
NOTES="${2:-}"
TEAM="${PERKLE_TEAM:-739RVEUAP4}"
TAG="v$VERSION"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/build/release"
ARCHIVE="$OUT/Perkle.xcarchive"
DMG="$OUT/Perkle-$VERSION.dmg"

cd "$ROOT"

# Preflight: fail before the slow steps, not after them.
[[ -z "$(git status --porcelain)" ]] || { echo "Working tree is not clean." >&2; exit 1; }
! git rev-parse -q --verify "refs/tags/$TAG" >/dev/null || { echo "Tag $TAG already exists." >&2; exit 1; }
grep -q "MARKETING_VERSION = $VERSION;" Perkle.xcodeproj/project.pbxproj \
    || { echo "MARKETING_VERSION in the project is not $VERSION." >&2; exit 1; }

rm -rf "$OUT" && mkdir -p "$OUT"

export_options() { # $1 = destination: export | upload
    cat <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>developer-id</string>
    <key>teamID</key><string>$TEAM</string>
    <key>signingStyle</key><string>automatic</string>
    <key>destination</key><string>$1</string>
</dict>
</plist>
EOF
}

# 1. Archive, then upload a Developer ID signed copy to Apple's notary service.
xcodebuild archive -project Perkle.xcodeproj -scheme Perkle -configuration Release \
    -archivePath "$ARCHIVE" DEVELOPMENT_TEAM="$TEAM" -allowProvisioningUpdates -quiet
export_options upload >"$OUT/upload.plist"
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist "$OUT/upload.plist" \
    -exportPath "$OUT/upload" -allowProvisioningUpdates -quiet

# 2. Wait for notarization, then export the stapled app (up to 30 minutes).
echo "Waiting for notarization..."
for _ in $(seq 1 60); do
    if xcodebuild -exportNotarizedApp -archivePath "$ARCHIVE" -exportPath "$OUT/notarized" >"$OUT/notarize.log" 2>&1; then
        break
    fi
    if grep -qiE "invalid|rejected" "$OUT/notarize.log"; then
        cat "$OUT/notarize.log" >&2; exit 1
    fi
    sleep 30
done
APP="$OUT/notarized/Perkle.app"
[[ -d "$APP" ]] || { echo "Notarization did not finish in time." >&2; cat "$OUT/notarize.log" >&2; exit 1; }
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose "$APP"

# 3. DMG with a drag-to-Applications shortcut. Staged outside the repo so
#    sync tools (Dropbox) can't add their extended attributes to the app.
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
ditto --norsrc --noextattr --noacl "$APP" "$STAGE/Perkle.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Perkle $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null

# 4. Tag and publish.
git tag -a "$TAG" -m "Perkle $VERSION"
git push origin "$TAG"
if [[ -n "$NOTES" ]]; then
    gh release create "$TAG" "$DMG" --title "Perkle $VERSION" --notes-file "$NOTES"
else
    gh release create "$TAG" "$DMG" --title "Perkle $VERSION" --generate-notes
fi
echo "Released $TAG: $(gh release view "$TAG" --json url -q .url)"

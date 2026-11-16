#!/bin/zsh
# Builds a Developer ID release of Activity Inspector: archive, export, notarize, staple, then a
# signed, notarized and stapled DMG. Every step is checked; any failure stops the script.
#
#   scripts/release.sh
#
# Needs, once per Mac: the "Developer ID Application: Peter A. Jones (8QQC2WMRHS)" certificate in
# the keychain, and notarization credentials stored under the profile below with
#   xcrun notarytool store-credentials "ActivityInspector" --apple-id <Apple ID> --team-id 8QQC2WMRHS
# Output goes to build/release/ (ignored by git).
set -euo pipefail

TEAM=8QQC2WMRHS
PROFILE=ActivityInspector
APP_NAME="Activity Inspector"
ROOT=${0:A:h:h}
OUT="$ROOT/build/release"
ARCHIVE="$OUT/ActivityInspector.xcarchive"
EXPORT="$OUT/export"
APP="$EXPORT/$APP_NAME.app"
HELPER="$APP/Contents/MacOS/ActivityInspectorHelper"

# The rules the app and helper check each other against (HelperShared.swift, Release build).
CLIENT_REQ='anchor apple generic and identifier "ca.peter-jones.ActivityInspector" and certificate leaf[subject.OU] = "'$TEAM'" and !entitlement["com.apple.security.get-task-allow"]'
HELPER_REQ='anchor apple generic and identifier "ActivityInspectorHelper" and certificate leaf[subject.OU] = "'$TEAM'"'

step() { print -P "\n%B==> $1%b"; }
fail() { print -u2 "release: $1"; exit 1; }

step "Checking the signing certificate and notarization profile"
security find-identity -v -p codesigning | grep -q "Developer ID Application: .*($TEAM)" \
    || fail "no Developer ID Application certificate for team $TEAM in the keychain"
xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null \
    || fail "notarization profile \"$PROFILE\" missing or rejected (see the header of this script)"

rm -rf "$OUT"; mkdir -p "$OUT"

step "Archiving (Release)"
xcodebuild -project "$ROOT/ActivityInspector.xcodeproj" -scheme ActivityInspector \
    -configuration Release -destination 'generic/platform=macOS' \
    -archivePath "$ARCHIVE" archive > "$OUT/archive.log" 2>&1 \
    || { tail -30 "$OUT/archive.log"; fail "archive failed (full log: $OUT/archive.log)"; }

step "Exporting with Developer ID"
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$EXPORT" \
    -exportOptionsPlist "$ROOT/scripts/ExportOptions.plist" -allowProvisioningUpdates \
    > "$OUT/export.log" 2>&1 \
    || { tail -30 "$OUT/export.log"; fail "export failed (full log: $OUT/export.log)"; }

VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$APP/Contents/Info.plist")
DMG="$OUT/ActivityInspector-$VERSION.dmg"

step "Checking signatures ($VERSION, build $BUILD)"
codesign --verify --strict --deep "$APP" || fail "the app's signature doesn't verify"
for item in "$APP" "$HELPER"; do
    details=$(codesign -dvv "$item" 2>&1)
    print -r -- "$details" | grep -q "^Authority=Developer ID Application: .*($TEAM)" \
        || fail "$item is not signed with Developer ID"
    print -r -- "$details" | grep -q "flags=.*runtime" || fail "$item lacks the hardened runtime"
    print -r -- "$details" | grep -q "^Timestamp=" || fail "$item has no secure timestamp"
done
codesign -v -R="$CLIENT_REQ" "$APP" || fail "the app fails the helper's client requirement"
codesign -v -R="$HELPER_REQ" "$HELPER" || fail "the helper fails the app's requirement"

notarize() {   # notarize <file>: submits and waits; prints Apple's log when it's rejected
    local result id
    result=$(xcrun notarytool submit "$1" --keychain-profile "$PROFILE" --wait --output-format plist)
    id=$(print -r -- "$result" | plutil -extract id raw -)
    if [[ $(print -r -- "$result" | plutil -extract status raw -) != Accepted ]]; then
        xcrun notarytool log "$id" --keychain-profile "$PROFILE"
        fail "notarization of $(basename "$1") was not accepted"
    fi
    print "Accepted ($id)"
}

step "Notarizing the app"
ditto -c -k --keepParent "$APP" "$OUT/app.zip"
notarize "$OUT/app.zip"
xcrun stapler staple "$APP"

step "Building the DMG"
STAGE="$OUT/dmg"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/$APP_NAME.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
codesign --sign "Developer ID Application: Peter A. Jones ($TEAM)" --timestamp "$DMG"

step "Notarizing the DMG"
notarize "$DMG"
xcrun stapler staple "$DMG"

step "Gatekeeper check"
spctl --assess --type execute --verbose=2 "$APP"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
xcrun stapler validate "$DMG"

print -P "\n%BDone:%b $DMG"

#!/bin/zsh
# Run Script phase "Helper launchd plist" on the app target. Two jobs:
#
# 1. In a Debug or Release build, refuse settings that have drifted. The two differ in bundle ID,
#    display name and icon (Debug is "Activity Inspector Dev", ca.peter-jones.ActivityInspector.dev), and
#    Xcode's General tab can silently flatten per-configuration values onto one (FB24809836).
# 2. Write the privileged helper's launchd property list into the app, named and labelled from the
#    bundle ID, so each configuration registers its own helper and a Debug build never shares
#    macOS's background-item records with the release.
#
# Reads only build settings from the environment. The phase declares $SCRIPT_OUTPUT_FILE_0 as
#   $(TARGET_BUILD_DIR)/$(CONTENTS_FOLDER_PATH)/Library/LaunchDaemons/$(PRODUCT_BUNDLE_IDENTIFIER).helper.plist
# See docs/superpowers/specs/2026-11-16-debug-bundle-id-design.md.
set -euo pipefail

failed=0
expect() {   # expect <setting name> <expected value>
    local actual=${(P)1-}
    if [[ "$actual" != "$2" ]]; then
        print -u2 "error: $CONFIGURATION: $1 is '$actual', expected '$2'. Fix it in Build Settings, not the General tab (FB24809836). See docs/superpowers/specs/2026-11-16-debug-bundle-id-design.md."
        failed=1
    fi
}
expect_debug_flag() {   # expect_debug_flag yes|no: whether SWIFT_ACTIVE_COMPILATION_CONDITIONS holds DEBUG
    local has=no
    [[ " ${SWIFT_ACTIVE_COMPILATION_CONDITIONS-} " == *" DEBUG "* ]] && has=yes
    if [[ $has != "$1" ]]; then
        print -u2 "error: $CONFIGURATION: SWIFT_ACTIVE_COMPILATION_CONDITIONS is '${SWIFT_ACTIVE_COMPILATION_CONDITIONS-}'; DEBUG must be $([[ $1 == yes ]] && print present || print absent). HelperConstants picks the helper's names from it."
        failed=1
    fi
}
# Both directions matter: a Release build with Dev values ships the wrong app, and a Debug build
# with Release values shares the release's helper registration again (the 2026-11-16 failure).
case "${CONFIGURATION:-}" in
    Release)
        expect PRODUCT_BUNDLE_IDENTIFIER "ca.peter-jones.ActivityInspector"
        expect INFOPLIST_KEY_CFBundleDisplayName "Activity Inspector"
        expect ASSETCATALOG_COMPILER_APPICON_NAME "ActivityInspector"
        expect_debug_flag no ;;
    Debug)
        expect PRODUCT_BUNDLE_IDENTIFIER "ca.peter-jones.ActivityInspector.dev"
        expect INFOPLIST_KEY_CFBundleDisplayName "Activity Inspector Dev"
        expect ASSETCATALOG_COMPILER_APPICON_NAME "ActivityInspectorDev"
        expect_debug_flag yes ;;
esac
(( failed == 0 )) || exit 1

: "${PRODUCT_BUNDLE_IDENTIFIER:?}" "${SCRIPT_OUTPUT_FILE_0:?}"
label="$PRODUCT_BUNDLE_IDENTIFIER.helper"
plist=$SCRIPT_OUTPUT_FILE_0
mkdir -p "${plist:h}"
rm -f "$plist"
# PlistBuddy, not plutil: plutil's key paths split on ".", and the label is full of dots.
pb() { /usr/libexec/PlistBuddy -c "$1" "$plist" >/dev/null; }
pb "Add :Label string $label"
pb "Add :BundleProgram string Contents/MacOS/ActivityInspectorHelper"
pb "Add :MachServices dict"
pb "Add :MachServices:$label bool true"
pb "Add :AssociatedBundleIdentifiers array"
pb "Add :AssociatedBundleIdentifiers:0 string $PRODUCT_BUNDLE_IDENTIFIER"
plutil -lint -s "$plist"

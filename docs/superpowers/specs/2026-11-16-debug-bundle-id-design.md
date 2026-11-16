# Debug builds get their own identity — design (2026-11-16)

## Why

The Debug build and the Developer ID release share the bundle ID `ca.peter-jones.ActivityInspector`.
On 2026-11-16 that cost real time twice: macOS's background-item records pointed at different
copies, so launchd refused to spawn the helper (`EX_CONFIG`, fixed only by `sfltool resetbtm` and a
restart); and quitting one copy quit the other, killing a test run part-way through.

## Goal

A Debug build and the release are two separate apps to macOS, and look it: own bundle ID, own name,
own icon, own helper registration, own preferences and Application Support folder. Follows
PocketScanner's pattern (`DocumentScanner/docs/dev-build.md` there).

| | Release | Debug |
|---|---|---|
| Bundle ID | `ca.peter-jones.ActivityInspector` | `ca.peter-jones.ActivityInspector.dev` |
| Display name and `CFBundleName` (app menu) | Activity Inspector | Activity Inspector Dev |
| App icon | `ActivityInspector` (VFD green) | `ActivityInspectorDev` (VFD green + amber "DEV" corner ribbon, "D2") |
| Helper label / Mach service | `ca.peter-jones.ActivityInspector.helper` | `ca.peter-jones.ActivityInspector.dev.helper` |
| Helper's client requirement | identifier `…ActivityInspector`, no `get-task-allow` | identifier `…ActivityInspector.dev` |

**Non-goals:** changing the Release build in any way; changing `PRODUCT_NAME` (the `.app` folder and
process stay `Activity Inspector`, so `TEST_HOST` keeps working — at the cost that `pgrep -x`,
`pkill` and `killall` by name now match both copies); a separate helper signing identifier (stays
`ActivityInspectorHelper`, which is the same in both and needs no change).

**Anti-goal:** anything Debug-only (plist, icon, `DEBUG` code) reaching a Release archive.

**Accepted consequence:** Debug runs and the unit tests (the test host is the Debug app) use their own
preferences and battery history, not Peter's everyday copy's. Tests stop seeing his customisations,
and running the tests should no longer end the release copy (confirm once by hand).

## Approaches

1. **Generate the launchd plist at build time from the build settings** — chosen by Peter. One source,
   a Release build can never carry Debug's plist, nothing to drift.
2. Two hand-written plists copied into every build, app registers the matching one — rejected: Release
   ships an unused Dev plist and the two files can drift.

Icon: Peter chose D2, today's green icon with an amber "DEV" corner ribbon, over an all-amber icon (D1)
and an all-blue one (D3). Accepted trade-off: at 32 px (e.g. Login Items) the word is unreadable and
only an amber corner shows. Variants sheet is in the session scratchpad only.

## Design

- **Per-configuration app-target settings:** `PRODUCT_BUNDLE_IDENTIFIER`,
  `INFOPLIST_KEY_CFBundleDisplayName`, `CFBundleName` (the app menu; via the generated Info.plist key
  if Xcode offers one, otherwise the builder finds the supported way) and
  `ASSETCATALOG_COMPILER_APPICON_NAME`, as in the table. `AppName.display` stays "Activity Inspector"
  (it names the product in text); `AppNameTests` changes to match what Debug now reports.
- **Dev icon:** `ActivityInspector/ActivityInspectorDev.icon`, a copy of `ActivityInspector.icon` with one
  more group on top: a ribbon across the top-right corner (45°, amber `#FFBF33`) carrying "DEV" in
  near-black bold capitals, as outlines (no SVG text), glass off and no shadow so it stays flat and
  crisp. The meters and background are unchanged. Recorded in `design/icon/README.md`. The builder confirms a Release build's asset catalog
  does not contain it (if it does, find a setting that excludes it).
- **Plist step (one Run Script phase on the app target):** writes
  `$(TARGET_BUILD_DIR)/$(CONTENTS_FOLDER_PATH)/Library/LaunchDaemons/$(PRODUCT_BUNDLE_IDENTIFIER).helper.plist`
  (declared as the phase's output, required by `ENABLE_USER_SCRIPT_SANDBOXING = YES`; not
  `BUILT_PRODUCTS_DIR`, a symlink while archiving) with Label and MachServices =
  `$(PRODUCT_BUNDLE_IDENTIFIER).helper`, `BundleProgram` `Contents/MacOS/ActivityInspectorHelper`,
  `AssociatedBundleIdentifiers` = the bundle ID. Signing runs after all phases, so the plist is sealed.
  It replaces the hand-written `LaunchDaemons/…helper.plist` and its Copy Files entry.
- **Release guard, in the same phase** (a separate phase can't read the generated file under the
  script sandbox): when `CONFIGURATION` is Release, fail unless the bundle ID is
  `ca.peter-jones.ActivityInspector`, the display name is `Activity Inspector`, the icon name is
  `ActivityInspector`, and `SWIFT_ACTIVE_COMPILATION_CONDITIONS` has no `DEBUG`. (Xcode's General tab
  can flatten per-configuration values onto one, FB24809836.)
- **Swift:** `HelperConstants` derives its names from one pure function, e.g. `identity(debug:)`, with a
  single `#if DEBUG` choosing the branch (the pattern `clientRequirement(debug:)` already uses and
  `PrivilegedHelperTests` tests both ways). `DEBUG` is set only at project level, so it reaches both
  targets.
- **Tests:** both branches of `identity(debug:)`; `Bundle.main.bundleIdentifier + ".helper" ==
  machServiceName` (ties the build setting to the Swift constant); the bundled plist's Label,
  MachServices and AssociatedBundleIdentifiers match `HelperConstants`, and `Library/LaunchDaemons`
  holds exactly one file; `noSourceFileSaysTheOldName` drops the removed `LaunchDaemons` folder.
- **`scripts/release.sh`:** also checks the archived app's plist Label and AssociatedBundleIdentifiers
  are the Release ones and that `strings` on the helper shows no `.dev.helper`; deletes
  `build/release/export/` and `build/release/dmg/` once the DMG is built, so no loose Release-ID
  copies sit around to be launched.
- **Scheme:** the Profile action builds Release today (`ActivityInspector.xcscheme`); switch it to
  Debug so Instruments runs don't produce another Release-ID copy.
- **pbxproj edits** (Peter makes them in Xcode from exact clicks, or approves Claude making them):
  per-configuration settings, the Run Script phase, removing the old plist's Copy Files entry and file
  reference. The scheme file and the `.icon` folder are not the pbxproj.
- **One clean build after the change,** so the old copied plist doesn't linger in the Debug products.
- **Docs:** CLAUDE.md — helper section (names per configuration, the Dev helper needs its own approval
  and accepts debuggable clients, unregister it before deleting DerivedData or it is orphaned like
  today's), process-name ambiguity (tell copies apart with `pgrep -fl` / path or bundle ID), test host
  preferences and the `defaults` path gotcha now name the `.dev` domain. `TODO.md`'s `.debug` → `.dev`,
  ticked when done. `BatteryHistory.swift` line 69 comment.

## Left to the builder

Exact script text, PlistBuddy vs `plutil` usage, where the phase sits relative to Copy Files, the
precise Xcode clicks for Peter, and how to keep the Dev icon out of Release if it turns out to be
included.
